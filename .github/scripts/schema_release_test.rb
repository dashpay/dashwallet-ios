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
    attr_reader :dispatches
    def initialize
      @registry = { "format_version" => 1, "schemas" => {}, "releases" => {} }
      @dispatches = []
    end
    def file(*_args)
      SchemaRelease.json(@registry)
    end
    def dispatch(id, commit)
      @dispatches << [id, commit]
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

  class Apple
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
    def published_versions(_app)
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
    Dir.mktmpdir do |dir|
      path = File.join(dir, SchemaRelease::REGISTRY)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, SchemaRelease.json(@store.github.registry))
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

  def test_observed_release_remains_required_after_removal_from_sale
    @pipeline.sync
    @apple.versions = []
    @pipeline.sync
    assert_equal 2, @store.github.dispatches.length
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

class SchemaDataStoreTest < Minitest::Test
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
    attr_accessor :race, :files
    attr_reader :updates
    def initialize
      @head = "a" * 40
      @files, @blobs, @trees, @commits, @updates = {}, {}, {}, {}, []
    end
    def ref(*_args)
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
    store = SchemaRelease::Store.new(api)
    store.write({ "build.json" => "evidence" }, message: "record")
    assert_equal({ "other.json" => "other", "build.json" => "evidence" }, api.files)
    assert_equal 2, api.updates.length
    assert api.updates.all? { |body| body[:force] == false }
  end

  def test_atomic_retry_refuses_conflicting_evidence
    api = GitAPI.new
    api.race = { "build.json" => "different" }
    assert_raises(SchemaRelease::Error) { SchemaRelease::Store.new(api).write({ "build.json" => "evidence" }, message: "record") }
    assert_equal "different", api.files["build.json"]
  end

  def test_identical_evidence_is_a_noop
    api = GitAPI.new
    api.files = { "build.json" => "same" }
    SchemaRelease::Store.new(api).write({ "build.json" => "same" }, message: "record")
    assert_empty api.updates
  end
end
