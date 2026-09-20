# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "schema_release"

class SchemaReleaseTest < Minitest::Test
  BUNDLE = "org.dashfoundation.dash"
  SCHEMA = { "schema_version" => "2.0.0", "model_checksum" => "checksum", "entity_hashes" => { "Wallet" => "abcd" }, "indexes" => ["Wallet|index"] }.freeze

  class GitHub
    attr_accessor :registry
    attr_reader :dispatches, :retained_sources
    def initialize
      @registry = { "format_version" => 1, "schemas" => {}, "releases" => {} }
      @dispatches = []
      @retained_sources = []
    end
    def file(*_args)
      SchemaRelease.json(@registry)
    end
    def dispatch(id, commit)
      @dispatches << [id, commit]
    end
    def retain_platform_source(sha)
      @retained_sources << sha
    end
  end

  class Store
    attr_reader :files, :github, :writes
    def initialize
      @files, @github, @writes = {}, GitHub.new, []
    end
    def head
      "d" * 40
    end
    def read(path, commit: head, optional: false)
      return files[path] if files.key?(path) || optional
      raise SchemaRelease::Error, "Missing #{path}"
    end
    def document(path, **args)
      bytes = read(path, **args)
      bytes && JSON.parse(bytes)
    end
    def paths(prefix, **_args)
      files.keys.select { |path| path.start_with?(prefix) }
    end
    def write(values, message:, mutable: [])
      values.each do |path, bytes|
        raise SchemaRelease::Error, "Immutable #{path}" if files[path] && files[path] != bytes && !mutable.include?(path)
        files[path] = bytes
      end
      @writes << values
      head
    end
  end

  class Apple < AppStoreConnectRelease::Client
    attr_accessor :versions, :builds
    def initialize
      @versions = [version("old", "9.0.0"), version("new", "9.1.0")]
      @builds = { "new" => { "id" => "apple21", "attributes" => { "version" => "21" } } }
    end
    def version(id, number)
      { "id" => id, "attributes" => { "versionString" => number, "appVersionState" => "READY_FOR_DISTRIBUTION" } }
    end
    def find_app(_bundle)
      { "id" => "app" }
    end
    def app_store_versions(_app)
      versions
    end
    def version_build(id)
      builds.fetch(id)
    end
  end

  def setup
    @store, @apple = Store.new, Apple.new
    @store.files["baseline.json"] = SchemaRelease.json({ "bundle_id" => BUNDLE, "app_id" => "app", "max_app_version" => "9.0.0" })
    @pipeline = SchemaRelease::Pipeline.new(store: @store, apple: @apple, bundle_id: BUNDLE, output: StringIO.new)
    @fixture = "SQLite format 3\x00example"
    @digest = Digest::SHA256.hexdigest(@fixture)
    @manifest = { "format_version" => 1, "bundle_id" => BUNDLE, "app_version" => "9.1.0", "build_number" => "21",
                  "wallet_sha" => "a" * 40, "platform_sha" => "b" * 40, "schema" => SCHEMA,
                  "fixture_path" => "stores/#{@digest}.store", "fixture_sha256" => @digest }
    save_manifest
  end

  def save_manifest
    @path = SchemaRelease.manifest_path(BUNDLE, "9.1.0", "21")
    @store.files[@path] = SchemaRelease.json(@manifest)
    @store.files[@manifest.fetch("fixture_path")] = @fixture
  end

  def merge_release
    record = @pipeline.published_records.first
    manifest, _path, hash = @pipeline.evidence(record)
    @store.github.registry["releases"]["new"] = record.slice("bundle_id", "app_version", "build_number", "build_id", "app_id").merge(
      "schema_version" => "2.0.0", "platform_sha" => manifest["platform_sha"], "manifest_sha256" => hash)
    @store.github.registry["schemas"]["2.0.0"] = { "schema" => SCHEMA, "fixture_path" => "fixture.store", "fixture_sha256" => @digest }
  end

  def test_uses_published_build_21_not_latest_testflight_build_22
    extra_path = SchemaRelease.manifest_path(BUNDLE, "9.1.0", "22")
    @store.files[extra_path] = SchemaRelease.json(@manifest.merge("build_number" => "22", "platform_sha" => "c" * 40))
    @pipeline.sync
    proof = @store.document("releases/new.json")
    assert_equal "21", proof["build_number"]
    assert_equal @path, proof["manifest_path"]
    assert_equal [["new", @store.head]], @store.github.dispatches
  end

  def test_retry_reuses_immutable_observation_timestamp_and_commit
    @pipeline.sync
    original = @store.files["releases/new.json"]
    @pipeline.sync
    assert_equal original, @store.files["releases/new.json"]
    assert_equal 1, @store.github.dispatches.uniq.length
  end

  def test_no_dispatch_when_release_is_merged
    merge_release
    @pipeline.sync
    assert_empty @store.github.dispatches
    assert_equal "merged", @store.document("status/new.json")["state"]
  end

  def test_dry_run_has_no_writes_or_dispatches
    @pipeline.sync(dry_run: true)
    assert_empty @store.writes
    assert_empty @store.github.dispatches
  end

  def test_manual_id_must_be_a_published_post_baseline_version
    assert_raises(SchemaRelease::Error) { @pipeline.sync(release_id: "unpublished") }
    assert_raises(SchemaRelease::Error) { @pipeline.sync(release_id: "old") }
  end

  def test_missing_manifest_fails_without_guessing
    @store.files.delete(@path)
    assert_raises(SchemaRelease::Error) { @pipeline.sync }
    assert_empty @store.github.dispatches
  end

  def test_sync_reports_bad_evidence_but_still_dispatches_other_valid_releases
    @apple.versions.insert(1, @apple.version("broken", "9.0.1"))
    @apple.builds["broken"] = { "id" => "apple20", "attributes" => { "version" => "20" } }
    error = assert_raises(SchemaRelease::Error) { @pipeline.sync }
    assert_includes error.message, "broken"
    assert_equal [["new", @store.head]], @store.github.dispatches
    assert_nil @store.document("releases/broken.json", optional: true)
    refute_nil @store.document("releases/new.json")
    with_platform do |directory|
      assert_raises(SchemaRelease::Error) { @pipeline.gate(directory) }
    end
  end

  def test_wrong_fixture_digest_fails
    @store.files[@manifest.fetch("fixture_path")] = "changed"
    assert_raises(SchemaRelease::Error) { @pipeline.sync }
  end

  def test_manifest_identity_must_match_apple_build
    @manifest["build_number"] = "22"
    save_manifest
    assert_raises(SchemaRelease::Error) { @pipeline.sync }
  end

  def test_published_build_cannot_change_on_retry
    @pipeline.sync
    @apple.builds["new"]["id"] = "another-build"
    assert_raises(SchemaRelease::Error) { @pipeline.sync }
  end

  def test_registry_cannot_change_indexes_for_same_schema
    merge_release
    @store.github.registry["schemas"]["2.0.0"]["schema"] = SCHEMA.merge("indexes" => ["different-index"])
    assert_raises(SchemaRelease::Error) { @pipeline.sync }
  end

  def test_gate_requires_merge_and_presence_in_selected_commit
    with_platform do |dir|
      path = File.join(dir, SchemaRelease::REGISTRY)
      assert_raises(SchemaRelease::Error) { @pipeline.gate(dir) }
      merge_release
      assert_raises(SchemaRelease::Error) { @pipeline.gate(dir) }
      File.write(path, SchemaRelease.json(@store.github.registry))
      File.binwrite(File.join(dir, "fixture.store"), @fixture)
      @pipeline.gate(dir)
      File.binwrite(File.join(dir, "fixture.store"), "broken")
      assert_raises(SchemaRelease::Error) { @pipeline.gate(dir) }
    end
  end

  def with_platform
    Dir.mktmpdir do |dir|
      SchemaRelease::CAPTURE_FILES.each do |relative|
        path = File.join(dir, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "test capture support")
      end
      path = File.join(dir, SchemaRelease::REGISTRY)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, SchemaRelease.json(@store.github.registry))
      yield dir
    end
  end

  def test_gate_checks_setup_even_without_post_baseline_publications
    @apple.versions = []
    with_platform do |dir|
      @pipeline.gate(dir)
      @store.files.delete("baseline.json")
      error = assert_raises(SchemaRelease::Error) { @pipeline.gate(dir) }
      assert_match "bootstrap", error.message
      assert_match "dry_run disabled", error.message
    end
  end

  def test_gate_explains_selected_checkout_missing_release_support_before_apple_access
    @apple.define_singleton_method(:find_app) { |_bundle| raise "Apple must not be contacted" }
    with_platform do |dir|
      [SchemaRelease::REGISTRY, SchemaRelease::CAPTURE_FILES.last].each do |relative|
        path = File.join(dir, relative)
        original = File.read(path)
        File.delete(path)
        error = assert_raises(SchemaRelease::Error) { @pipeline.gate(dir) }
        assert_includes error.message, dir
        assert_includes error.message, relative
        assert_includes error.message, "Select a Platform commit"
        File.write(path, original)
      end
    end
  end

  def test_gate_rejects_invalid_registry_even_without_publications
    @apple.versions = []
    with_platform do |dir|
      ["not-json", '{"format_version":2,"schemas":{},"releases":{}}', '{}'].each do |bytes|
        File.write(File.join(dir, SchemaRelease::REGISTRY), bytes)
        error = assert_raises(SchemaRelease::Error) { @pipeline.gate(dir) }
        assert_match "registry", error.message
      end
    end
  end

  def test_gate_explains_unavailable_or_forbidden_merged_registry
    @apple.versions = []
    with_platform do |dir|
      [nil, SchemaRelease::HTTPError.new(403, "forbidden")].each do |result|
        @store.github.define_singleton_method(:file) do |*_args, **_options|
          raise result if result.is_a?(Exception)
          result
        end
        error = assert_raises(SchemaRelease::Error) { @pipeline.gate(dir) }
        assert_includes error.message, SchemaRelease::PLATFORM_REPO
        assert_includes error.message, SchemaRelease::REGISTRY
        assert_includes error.message, "SCHEMA_RELEASE_TOKEN"
      end
    end
  end

  def test_absent_registry_entry_is_distinct_from_incomplete_or_conflicting_evidence
    record = @pipeline.published_records.first
    manifest, _path, hash = @pipeline.evidence(record)
    refute @pipeline.registered?(@store.github.registry, record, manifest, hash)
    merge_release
    assert @pipeline.registered?(@store.github.registry, record, manifest, hash)
    original = @store.github.registry["releases"]["new"].dup
    @store.github.registry["releases"]["new"].delete("platform_sha")
    assert_raises(SchemaRelease::Error) { @pipeline.registered?(@store.github.registry, record, manifest, hash) }
    @store.github.registry["releases"]["new"] = original.merge("platform_sha" => "f" * 40)
    assert_raises(SchemaRelease::Error) { @pipeline.registered?(@store.github.registry, record, manifest, hash) }
  end

  def test_observed_release_remains_required_after_removal_from_sale
    @pipeline.sync
    @apple.versions = []
    @pipeline.sync
    assert_equal 2, @store.github.dispatches.length
    with_platform do |dir|
      assert_raises(SchemaRelease::Error) { @pipeline.gate(dir) }
    end
  end

  def test_manual_retry_uses_retained_publication_when_apple_no_longer_lists_it
    @pipeline.sync
    original = @store.files.fetch("releases/new.json")
    @apple.versions = []

    @pipeline.sync(release_id: "new")

    assert_equal [["new", @store.head], ["new", @store.head]], @store.github.dispatches
    assert_equal original, @store.files.fetch("releases/new.json")
    assert_equal "apple21", @store.document("releases/new.json").fetch("build_id")
  end

  def test_manual_retry_of_retained_publication_keeps_dry_run_read_only
    @pipeline.sync
    @apple.versions = []
    writes = @store.writes.length
    dispatches = @store.github.dispatches.length

    @pipeline.sync(release_id: "new", dry_run: true)

    assert_equal writes, @store.writes.length
    assert_equal dispatches, @store.github.dispatches.length
  end

  def test_manual_retry_of_retained_publication_still_validates_build_evidence
    @pipeline.sync
    @apple.versions = []
    @store.files[@manifest.fetch("fixture_path")] = "changed"

    error = assert_raises(SchemaRelease::Error) { @pipeline.sync(release_id: "new") }

    assert_includes error.message, "Fixture digest does not match"
    assert_equal 1, @store.github.dispatches.length
  end

  def test_bootstrap_is_one_time_and_dry_run_is_read_only
    assert_raises(SchemaRelease::Error) { @pipeline.bootstrap }
    @store.files.delete("baseline.json")
    @pipeline.bootstrap(dry_run: true)
    refute @store.files.key?("baseline.json")
    @pipeline.bootstrap
    assert_equal "9.1.0", @store.document("baseline.json")["max_app_version"]
    assert_raises(SchemaRelease::Error) { @pipeline.bootstrap }
  end

  def test_pre_baseline_ambiguous_history_does_not_block_observation_or_gate
    @apple.versions.unshift({ "id" => "legacy", "attributes" => {
      "versionString" => "6.0.0", "appStoreState" => "REMOVED_FROM_SALE"
    } })
    @pipeline.sync
    assert_equal [["new", @store.head]], @store.github.dispatches
    merge_release
    with_platform do |dir|
      File.binwrite(File.join(dir, "fixture.store"), @fixture)
      @pipeline.gate(dir)
    end
  end

  def test_bootstrap_accepts_latest_known_publication_despite_older_ambiguous_history
    @store.files.delete("baseline.json")
    @apple.versions.unshift({ "id" => "legacy", "attributes" => {
      "versionString" => "6.0.0", "appStoreState" => "DEVELOPER_REMOVED_FROM_SALE"
    } })

    @pipeline.bootstrap

    assert_equal "9.1.0", @store.document("baseline.json").fetch("max_app_version")
    assert_equal "new", @store.document("baseline.json").fetch("release_id")
  end

  def test_ambiguous_history_after_baseline_still_blocks_sync_gate_and_bootstrap
    @apple.versions << { "id" => "ambiguous", "attributes" => {
      "versionString" => "9.2.0", "appStoreState" => "REMOVED_FROM_SALE"
    } }
    assert_raises(SchemaRelease::Error) { @pipeline.sync }
    with_platform do |dir|
      assert_raises(SchemaRelease::Error) { @pipeline.gate(dir) }
    end
    @store.files.delete("baseline.json")
    assert_raises(SchemaRelease::Error) { @pipeline.bootstrap }
    refute @store.files.key?("baseline.json")
    assert_empty @store.github.dispatches
  end

  def test_interrupted_upload_can_bind_later_using_build_tuple
    env = { "BUNDLE_ID" => BUNDLE, "EFFECTIVE_VERSION" => "9.1.0", "BUILD_NUMBER" => "21", "ASC_BUILD_ID" => "apple21" }
    SchemaRelease.bind_build(@store, env)
    SchemaRelease.bind_build(@store, env)
    assert_equal @path, @store.document("apple-builds/apple21.json")["manifest_path"]
    # Publication also works when the workflow crashed before this index write.
    @store.files.delete("apple-builds/apple21.json")
    @pipeline.sync
    assert_equal "apple21", @store.document("releases/new.json")["build_id"]
  end

  def test_record_build_preserves_capture_and_refuses_reused_tuple
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "schema.json"), SchemaRelease.json(SCHEMA))
      File.binwrite(File.join(dir, "fixture.store"), @fixture)
      File.write(File.join(dir, "toolchain.json"), '{"xcode":"26.6","simulator_runtime":"iOS-26"}')
      env = { "BUNDLE_ID" => BUNDLE, "EFFECTIVE_VERSION" => "9.2.0", "BUILD_NUMBER" => "1", "WALLET_SHA" => "a" * 40,
              "PLATFORM_SHA" => "b" * 40, "GITHUB_RUN_ID" => "1", "GITHUB_RUN_ATTEMPT" => "1" }
      SchemaRelease.record_build(@store, dir, env)
      SchemaRelease.record_build(@store, dir, env)
      assert_equal ["b" * 40, "b" * 40], @store.github.retained_sources
      env["PLATFORM_SHA"] = "c" * 40
      assert_raises(SchemaRelease::Error) { SchemaRelease.record_build(@store, dir, env) }
    end
  end

  def test_allocates_after_apple_builds_and_reserved_failed_uploads
    env = { "BUNDLE_ID" => BUNDLE, "EFFECTIVE_VERSION" => "9.1.0", "MIN_BUILD_NUMBER" => "21" }
    assert_equal 22, SchemaRelease.next_build(@store, env)
    env["MIN_BUILD_NUMBER"] = "25"
    assert_equal 25, SchemaRelease.next_build(@store, env)
    env["EFFECTIVE_VERSION"] = "9.2.0"
    env["MIN_BUILD_NUMBER"] = "1"
    assert_equal 1, SchemaRelease.next_build(@store, env)
  end

  def test_existing_apple_build_binding_cannot_point_elsewhere
    @store.files["apple-builds/apple21.json"] = SchemaRelease.json({ "manifest_path" => "different", "manifest_sha256" => "bad" })
    assert_raises(SchemaRelease::Error) { @pipeline.sync }
  end

  def test_rejects_path_injection_and_missing_fingerprint
    assert_raises(SchemaRelease::Error) { SchemaRelease.manifest_path(BUNDLE, "../../main", "21") }
    assert_raises(SchemaRelease::Error) { SchemaRelease.validate_schema(SCHEMA.merge("entity_hashes" => {})) }
    assert_raises(SchemaRelease::Error) { SchemaRelease.validate_schema(SCHEMA.merge("indexes" => %w[z a])) }
  end
end

class SchemaGitHubRequestTest < Minitest::Test
  Response = Struct.new(:code, :body)

  def setup
    @api = SchemaRelease::GitHub.new("private-test-token")
    @calls, @sleeps = [], []
  end

  def with_responses(outcomes)
    calls = @calls
    http = Struct.new(:max_retries).new
    http.define_singleton_method(:request) do |request|
      calls << request.method
      raise "Net::HTTP retry budget was not disabled" unless max_retries == 0
      outcome = outcomes.fetch(calls.length - 1)
      raise outcome if outcome.is_a?(Exception)
      outcome
    end
    transport = ->(*_args, **_options, &block) { block.call(http) }
    original_start = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start, transport)
    sleeps = @sleeps
    @api.define_singleton_method(:sleep) { |seconds| sleeps << seconds }
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original_start) if original_start
    @api.singleton_class.remove_method(:sleep) if @api.singleton_methods.include?(:sleep)
  end

  def test_transient_transport_failures_retry_reads
    [SocketError, IOError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
     Errno::ECONNRESET, OpenSSL::SSL::SSLError].each do |type|
      @calls.clear
      @sleeps.clear
      with_responses([type.new("private-test-token"), Response.new("200", '{"ok":true}')]) do
        assert_equal({ "ok" => true }, @api.request("get", "repos/example/test"))
      end
      assert_equal %w[GET GET], @calls
      assert_equal [1], @sleeps
    end
  end

  def test_read_retry_budget_is_four_attempts_with_bounded_backoff
    with_responses(Array.new(4) { SocketError.new("private-test-token") }) do
      error = assert_raises(SchemaRelease::Error) { @api.request("get", "repos/example/test") }
      assert_match "4 attempt", error.message
      refute_includes error.message, "private-test-token"
    end
    assert_equal 4, @calls.length
    assert_equal [1, 2, 4], @sleeps
  end

  def test_retries_only_transient_http_reads
    with_responses([Response.new("429", ""), Response.new("503", ""), Response.new("200", '{}')]) do
      assert_equal({}, @api.request("get", "repos/example/test"))
    end
    assert_equal [1, 2], @sleeps
    @calls.clear
    @sleeps.clear
    with_responses([Response.new("403", "")]) do
      error = assert_raises(SchemaRelease::HTTPError) { @api.request("get", "repos/example/test") }
      assert_equal 403, error.status
    end
    assert_equal ["GET"], @calls
    assert_empty @sleeps
  end

  def test_does_not_retry_ambiguous_writes_or_print_transport_details
    %w[post patch].each do |method|
      [SocketError.new("private-test-token"), Response.new("503", "")].each do |failure|
        @calls.clear
        @sleeps.clear
        with_responses([failure]) do
          error = assert_raises(SchemaRelease::Error) { @api.request(method, "repos/example/test", {}) }
          assert_match "write may have completed", error.message
          assert_match "reconcile", error.message
          refute_includes error.message, "private-test-token"
        end
        assert_equal [method.upcase], @calls
        assert_empty @sleeps
      end
    end
  end

  def test_ref_conflicts_keep_the_http_status_for_atomic_store_recovery
    with_responses([Response.new("422", "")]) do
      error = assert_raises(SchemaRelease::HTTPError) { @api.request("patch", "repos/example/test", {}) }
      assert_equal 422, error.status
    end
    assert_equal ["PATCH"], @calls
  end

  def test_missing_token_has_setup_instructions_before_any_network_call
    [nil, "", "  "].each do |token|
      error = assert_raises(SchemaRelease::Error) do
        SchemaRelease.main(["gate", "--platform-dir", "/unused"], { "SCHEMA_RELEASE_TOKEN" => token })
      end
      assert_includes error.message, "Add the Actions secret"
    end
  end

  def source_tag(commit = "b" * 40)
    { "ref" => "refs/tags/swift-schema-source/#{'b' * 40}", "object" => { "type" => "commit", "sha" => commit } }
  end

  def test_source_tag_is_created_once_and_never_updated
    with_responses([Response.new("404", ""), Response.new("201", JSON.generate(source_tag))]) do
      @api.retain_platform_source("b" * 40)
    end
    assert_equal %w[GET POST], @calls
    @calls.clear
    with_responses([Response.new("200", JSON.generate(source_tag))]) do
      @api.retain_platform_source("b" * 40)
    end
    assert_equal ["GET"], @calls
  end

  def test_source_tag_creation_race_reconciles_the_exact_commit
    with_responses([Response.new("404", ""), Response.new("422", "exists"), Response.new("200", JSON.generate(source_tag))]) do
      @api.retain_platform_source("b" * 40)
    end
    assert_equal %w[GET POST GET], @calls
  end

  def test_source_tag_conflict_is_never_overwritten
    with_responses([Response.new("200", JSON.generate(source_tag("c" * 40)))]) do
      error = assert_raises(SchemaRelease::Error) { @api.retain_platform_source("b" * 40) }
      assert_includes error.message, "without moving or deleting"
    end
    assert_equal ["GET"], @calls
  end

  def test_source_tag_ambiguous_write_stops_until_a_later_run_can_reconcile
    with_responses([Response.new("404", ""), SocketError.new("connection lost")]) do
      assert_raises(SchemaRelease::Error) { @api.retain_platform_source("b" * 40) }
    end
    assert_equal %w[GET POST], @calls
    assert_empty @sleeps
  end
end

class SchemaDataStoreTest < Minitest::Test
  def store_for(api)
    store = SchemaRelease::Store.new(api)
    @delays = []
    delays = @delays
    store.define_singleton_method(:sleep) { |seconds| delays << seconds }
    store
  end

  def test_large_fixture_uses_immutable_blob_fallback
    api = SchemaRelease::GitHub.new("test-token")
    calls = []
    api.define_singleton_method(:request) do |_method, path, **_options|
      calls << path
      if path.include?("/contents/")
        { "type" => "file", "encoding" => "none", "sha" => "a" * 40 }
      else
        { "encoding" => "base64", "content" => Base64.strict_encode64("fixture") }
      end
    end
    assert_equal "fixture", api.file("org/repo", "fixture.store", "b" * 40)
    assert_equal "repos/org/repo/git/blobs/#{'a' * 40}", calls.last
  end

  # Small Git API model exercises non-fast-forward conflicts without any network
  # or local repository writes.
  class GitAPI
    attr_accessor :race, :files, :stale_conflict_reads
    attr_reader :updates
    def initialize
      @head = "a" * 40
      @files, @blobs, @trees, @commits, @updates = {}, {}, {}, {}, []
    end
    def ref(*_args)
      if @stale_reads.to_i > 0
        @stale_reads -= 1
        return @stale_head
      end
      @head
    end
    def file(_repo, path, _ref, optional:)
      @files[path]
    end
    def request(method, path, body = nil, **_options)
      if path.end_with?("/blobs")
        key = "blob#{@blobs.length}"
        @blobs[key] = Base64.decode64(body.fetch(:content))
        { "sha" => key }
      elsif path.end_with?("/trees")
        key = "tree#{@trees.length}"
        @trees[key] = body.fetch(:tree)
        { "sha" => key }
      elsif method == "get" && path.include?("/commits/")
        { "tree" => { "sha" => "base" } }
      elsif path.end_with?("/commits")
        key = @commits.length.to_s(16).rjust(40, "0")
        @commits[key] = body
        { "sha" => key }
      elsif path.include?("/refs/heads/")
        @updates << body
        if @race
          @files.merge!(@race)
          @race = nil
          @stale_head, @stale_reads = @head, @stale_conflict_reads.to_i
          @head = "b" * 40
          raise SchemaRelease::HTTPError.new(422, "non-fast-forward")
        end
        candidate = @commits.fetch(body.fetch(:sha))
        raise "unexpected parent" unless candidate[:parents] == [@head]
        @trees.fetch(candidate[:tree]).each { |entry| @files[entry[:path]] = @blobs.fetch(entry[:sha]) }
        @head = body.fetch(:sha)
        {}
      else
        raise "Unexpected #{method} #{path}"
      end
    end
  end

  def test_atomic_retry_preserves_concurrent_unrelated_data
    api = GitAPI.new
    api.race = { "other.json" => "other" }
    store = store_for(api)
    store.write({ "build.json" => "evidence" }, message: "record")
    assert_equal({ "other.json" => "other", "build.json" => "evidence" }, api.files)
    assert_equal 2, api.updates.length
    assert api.updates.all? { |body| body[:force] == false }
  end

  def test_atomic_retry_refuses_conflicting_evidence
    api = GitAPI.new
    api.race = { "build.json" => "different" }
    assert_raises(SchemaRelease::Error) { store_for(api).write({ "build.json" => "evidence" }, message: "record") }
    assert_equal "different", api.files["build.json"]
  end

  def test_identical_evidence_is_a_noop
    api = GitAPI.new
    api.files = { "build.json" => "same" }
    SchemaRelease::Store.new(api).write({ "build.json" => "same" }, message: "record")
    assert_empty api.updates
  end

  def test_atomic_retry_waits_for_a_stale_ref_read_to_catch_up
    api = GitAPI.new
    api.race = { "other.json" => "other" }
    api.stale_conflict_reads = 2
    store_for(api).write({ "build.json" => "evidence" }, message: "record")
    assert_equal [1, 2, 4], @delays
    assert_equal 2, api.updates.length
    assert_equal({ "other.json" => "other", "build.json" => "evidence" }, api.files)
  end

  def test_unresolved_ref_conflict_has_bounded_reads_and_does_not_repeat_the_write
    api = GitAPI.new
    api.race = {}
    api.stale_conflict_reads = 10
    assert_raises(SchemaRelease::HTTPError) do
      store_for(api).write({ "build.json" => "evidence" }, message: "record")
    end
    assert_equal [1, 2, 4], @delays
    assert_equal 1, api.updates.length
    assert_empty api.files
  end
end
