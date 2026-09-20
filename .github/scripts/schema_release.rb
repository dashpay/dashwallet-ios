#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "app_store_connect_release"
require "digest"
require "open3"
require "optparse"

# Durable release evidence lives on an isolated Git branch. All reads used to
# dispatch Platform are pinned to a commit, and writes advance that branch with
# a non-forced ref update. A workflow retry may reuse evidence, never replace it.
module SchemaRelease
  Error = AppStoreConnectRelease::Error
  IOS_REPO = "dashpay/dashwallet-ios"
  PLATFORM_REPO = "dashpay/platform"
  DATA_BRANCH = "schema-release-data"
  PLATFORM_BRANCH = "v4.2-dev"
  REGISTRY = "packages/swift-sdk/schema-releases.json"
  CAPTURE_FILES = %w[
    packages/swift-sdk/schema-models.json
    packages/swift-sdk/scripts/freeze_schema_models.py
    packages/swift-sdk/SwiftTests/SwiftDashSDKTests/DashSchemaReleaseCaptureTests.swift
    packages/swift-sdk/SwiftTests/SwiftDashSDKTests/DashModelMigrationTests.swift
    packages/swift-sdk/SwiftTests/SwiftDashSDKTests/DashReleasedSchemaTests.swift
    packages/swift-sdk/SwiftTests/SwiftDashSDKTests/DashLegacySchemaMigrationTests.swift
  ].freeze
  TRANSPORT_ERRORS = [Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError].freeze

  def self.json(value)
    JSON.pretty_generate(value) + "\n"
  end

  def self.component(value)
    value = String(value)
    raise Error, "Unsafe or empty record identifier" unless value.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)
    value
  end

  def self.sha(value)
    raise Error, "Expected full Git commit SHA" unless String(value).match?(/\A[0-9a-f]{40}\z/)
    value
  end

  def self.manifest_path(bundle, version, build)
    "builds/#{component(bundle)}/#{component(version)}/#{component(build)}/manifest.json"
  end

  def self.validate_schema(schema)
    raise Error, "Invalid schema version" unless schema.fetch("schema_version").match?(/\A[1-9]\d*\.0\.0\z/)
    raise Error, "Missing schema checksum" if schema.fetch("model_checksum").empty?
    hashes = schema.fetch("entity_hashes")
    unless hashes.is_a?(Hash) && !hashes.empty? && hashes.all? { |name, hash| !name.empty? && hash.match?(/\A[0-9a-f]+\z/) }
      raise Error, "Invalid entity hash evidence"
    end
    indexes = schema.fetch("indexes")
    raise Error, "Invalid index evidence" unless indexes.is_a?(Array) && indexes.all? { |item| item.is_a?(String) }
    raise Error, "Index evidence must be sorted and unique" unless indexes == indexes.uniq.sort
    schema
  end

  class HTTPError < Error
    attr_reader :status
    def initialize(status, message)
      @status = status
      super(message)
    end
  end

  class GitHub
    def initialize(token)
      if token.nil? || token.strip.empty?
        raise Error, "SCHEMA_RELEASE_TOKEN is missing. Add the Actions secret to #{IOS_REPO} and #{PLATFORM_REPO} before running the schema release workflow."
      end
      @token = token
    end

    def request(method, path, body = nil, optional: false)
      uri = URI("https://api.github.com/#{path}")
      request = Net::HTTP.const_get(method.capitalize).new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/vnd.github+json"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body) if body
      attempts = 0
      begin
        attempts += 1
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 45) do |http|
          # Keep the four-attempt budget here, rather than also retrying in Net::HTTP.
          http.max_retries = 0
          http.request(request)
        end
        status = response.code.to_i
        return nil if optional && status == 404
        unless status.between?(200, 299)
          raise HTTPError.new(status, "GitHub #{method.upcase} #{uri.path} returned HTTP #{status}")
        end
        response.body.to_s.empty? ? {} : JSON.parse(response.body)
      rescue HTTPError => e
        transient = e.status == 429 || e.status >= 500
        if method == "get" && transient && attempts < 4
          sleep(2**(attempts - 1))
          retry
        end
        if method != "get" && transient
          raise HTTPError.new(e.status, "#{e.message}. The write may have completed; reconcile the remote result before retrying.")
        end
        raise
      rescue *TRANSPORT_ERRORS => e
        if method == "get" && attempts < 4
          sleep(2**(attempts - 1))
          retry
        end
        detail = method == "get" ? "Check connectivity and retry the workflow." :
          "The write may have completed; reconcile the remote result before retrying."
        raise Error, "GitHub #{method.upcase} #{uri.path} failed after #{attempts} attempt(s) (#{e.class}). #{detail}"
      end
    end

    def ref(repo, branch)
      request("get", "repos/#{repo}/git/ref/heads/#{branch}", optional: true)&.dig("object", "sha")
    end

    def file(repo, path, ref, optional: false)
      result = request("get", "repos/#{repo}/contents/#{path}?ref=#{URI.encode_www_form_component(ref)}", optional: optional)
      return nil unless result
      raise Error, "Expected a regular file at #{path}" unless result["type"] == "file"
      if result["encoding"] == "none"
        # The Contents endpoint omits bytes for files larger than 1 MiB.
        # Git blobs retain the same immutable identity and return base64.
        result = request("get", "repos/#{repo}/git/blobs/#{SchemaRelease.sha(result.fetch('sha'))}")
      end
      raise Error, "Unsupported GitHub file encoding at #{path}" unless result["encoding"] == "base64"
      Base64.decode64(result.fetch("content"))
    end

    def dispatch(release_id, data_commit)
      request("post", "repos/#{PLATFORM_REPO}/actions/workflows/swift-sdk-freeze-release.yml/dispatches",
              { ref: PLATFORM_BRANCH, inputs: { release_id: release_id, data_commit: data_commit } })
    end

    def retain_platform_source(commit)
      commit = SchemaRelease.sha(commit)
      ref = "refs/tags/swift-schema-source/#{commit}"
      path = "repos/#{PLATFORM_REPO}/git/ref/tags/swift-schema-source/#{commit}"
      existing = request("get", path, optional: true)
      unless existing
        begin
          existing = request("post", "repos/#{PLATFORM_REPO}/git/refs", { ref: ref, sha: commit })
        rescue HTTPError => error
          # A concurrent capture may have created exactly the same immutable tag.
          raise unless error.status == 422
          existing = request("get", path, optional: true)
          raise error unless existing
        end
      end
      unless existing["ref"] == ref && existing.dig("object", "type") == "commit" && existing.dig("object", "sha") == commit
        raise Error, "Platform source retention tag #{ref} does not match #{commit}; investigate without moving or deleting the tag."
      end
    end
  end

  class Store
    attr_reader :github
    def initialize(github)
      @github = github
    end

    def head
      github.ref(IOS_REPO, DATA_BRANCH)
    end

    def read(path, commit: head, optional: false)
      return nil if commit.nil? && optional
      raise Error, "Initialize schema-release-data first" unless commit
      github.file(IOS_REPO, path, commit, optional: optional)
    end

    def document(path, commit: head, optional: false)
      bytes = read(path, commit: commit, optional: optional)
      bytes && JSON.parse(bytes)
    end

    def paths(prefix, commit: head)
      return [] unless commit
      tree = github.request("get", "repos/#{IOS_REPO}/git/trees/#{commit}?recursive=1")
      raise Error, "Release data tree is truncated; refusing incomplete history" if tree["truncated"]
      tree.fetch("tree").select { |item| item["type"] == "blob" && item["path"].start_with?(prefix) }.map { |item| item["path"] }
    end

    def write(files, message:, mutable: [])
      5.times do
        parent = head
        changes = files.reject do |path, bytes|
          old = read(path, commit: parent, optional: true)
          if old && old != bytes && !mutable.include?(path)
            raise Error, "Immutable release evidence differs at #{path}; refusing overwrite"
          end
          old == bytes
        end
        return parent if changes.empty?
        entries = changes.map do |path, bytes|
          blob = github.request("post", "repos/#{IOS_REPO}/git/blobs", { content: Base64.strict_encode64(bytes), encoding: "base64" })
          { path: path, mode: "100644", type: "blob", sha: blob.fetch("sha") }
        end
        tree_body = { tree: entries }
        if parent
          base = github.request("get", "repos/#{IOS_REPO}/git/commits/#{parent}")
          tree_body[:base_tree] = base.fetch("tree").fetch("sha")
        end
        tree = github.request("post", "repos/#{IOS_REPO}/git/trees", tree_body)
        commit = github.request("post", "repos/#{IOS_REPO}/git/commits",
                                { message: message, tree: tree.fetch("sha"), parents: parent ? [parent] : [] }).fetch("sha")
        begin
          if parent
            github.request("patch", "repos/#{IOS_REPO}/git/refs/heads/#{DATA_BRANCH}", { sha: commit, force: false })
          else
            github.request("post", "repos/#{IOS_REPO}/git/refs", { ref: "refs/heads/#{DATA_BRANCH}", sha: commit })
          end
          return commit
        rescue HTTPError => e
          # Another writer advanced the branch. Re-read every affected path;
          # conflicting evidence is rejected on the next attempt.
          raise unless [409, 422].include?(e.status) && wait_for_new_head(parent)
        end
      end
      raise Error, "Release-data branch stayed busy after five atomic update attempts"
    end

    private

    def wait_for_new_head(parent)
      # A rejected ref update can be followed by a stale ref read. Retry reads,
      # never the ambiguous write, and revalidate all evidence on the next pass.
      [1, 2, 4].each do |delay|
        sleep(delay)
        return true if head != parent
      end
      false
    end
  end

  class Pipeline
    def initialize(store:, apple:, bundle_id:, output: $stdout)
      @store, @apple, @bundle, @out = store, apple, SchemaRelease.component(bundle_id), output
    end

    def bootstrap(dry_run: false)
      raise Error, "Baseline already exists; it must never be moved forward" if @store.document("baseline.json", optional: true)
      app = @apple.find_app(@bundle)
      newest = @apple.latest_published_version(app.fetch("id"))
      raise Error, "No published App Store version to accept as V1" unless newest
      baseline = { format_version: 1, bundle_id: @bundle, app_id: app.fetch("id"),
                   max_app_version: newest.fetch("attributes").fetch("versionString"),
                   release_id: newest.fetch("id"), schema_version: "1.0.0", accepted_at: Time.now.utc.iso8601 }
      @out.puts "Accepting existing App Store version #{baseline[:max_app_version]} as the V1 baseline."
      @store.write({ "baseline.json" => SchemaRelease.json(baseline) }, message: "Initialize SwiftData release baseline") unless dry_run
    end

    def published_records(&on_failure)
      baseline = @store.document("baseline.json", optional: true)
      unless baseline
        raise Error, "Schema release baseline is missing on #{IOS_REPO}:#{DATA_BRANCH}. Run 'Freeze published App Store schema' in bootstrap mode: inspect dry_run first, then repeat with dry_run disabled before building a release candidate."
      end
      raise Error, "Baseline belongs to a different app" unless baseline.fetch("bundle_id") == @bundle
      app = @apple.find_app(@bundle)
      raise Error, "App Store app identifier changed" unless baseline.fetch("app_id") == app.fetch("id")
      versions = @apple.published_versions(app.fetch("id"), after_version: baseline.fetch("max_app_version"))
      versions.filter_map do |version|
        attrs = version.fetch("attributes")
        number = attrs.fetch("versionString")
        next if AppStoreConnectRelease::MarketingVersion.new(number) <= AppStoreConnectRelease::MarketingVersion.new(baseline.fetch("max_app_version"))
        build = @apple.version_build(version.fetch("id"))
        {
          "format_version" => 1, "release_id" => SchemaRelease.component(version.fetch("id")),
          "app_id" => app.fetch("id"), "bundle_id" => @bundle, "app_version" => number,
          "build_number" => build.fetch("attributes").fetch("version"), "build_id" => SchemaRelease.component(build.fetch("id")),
          "observed_state" => attrs["appVersionState"] || attrs.fetch("appStoreState")
        }
      rescue Error, KeyError, JSON::ParserError => error
        # Observation can reconcile other publications, but callers such as
        # the candidate gate remain strict when no failure collector is supplied.
        raise unless on_failure
        on_failure.call(version["id"] || "unknown release", error)
        nil
      end
    end

    def evidence(record, commit: @store.head)
      path = SchemaRelease.manifest_path(@bundle, record.fetch("app_version"), record.fetch("build_number"))
      bytes = @store.read(path, commit: commit, optional: true)
      raise Error, "No captured evidence for App Store #{record['app_version']} (#{record['build_number']}); recover its original build evidence, never use the latest commit" unless bytes
      manifest = JSON.parse(bytes)
      raise Error, "Unsupported build manifest format" unless manifest.fetch("format_version") == 1
      %w[bundle_id app_version build_number].each do |key|
        raise Error, "Published build does not match #{path}" unless manifest.fetch(key) == record.fetch(key)
      end
      SchemaRelease.sha(manifest.fetch("platform_sha"))
      SchemaRelease.validate_schema(manifest.fetch("schema"))
      binding = @store.document("apple-builds/#{SchemaRelease.component(record.fetch('build_id'))}.json", commit: commit, optional: true)
      if binding && (binding.fetch("manifest_path") != path || binding.fetch("manifest_sha256") != Digest::SHA256.hexdigest(bytes))
        raise Error, "Apple build is already bound to different release evidence"
      end
      fixture_path = "stores/#{manifest.fetch('fixture_sha256')}.store"
      raise Error, "Invalid fixture path" unless fixture_path == manifest.fetch("fixture_path") && manifest.fetch("fixture_sha256").match?(/\A[0-9a-f]{64}\z/)
      store_bytes = @store.read(fixture_path, commit: commit)
      raise Error, "Fixture digest does not match" unless Digest::SHA256.hexdigest(store_bytes) == manifest.fetch("fixture_sha256")
      [manifest, path, Digest::SHA256.hexdigest(bytes)]
    end

    def registered?(registry, record, manifest, manifest_hash)
      release = registry.fetch("releases").fetch(record.fetch("release_id"), nil)
      return false unless release
      expected = record.slice("bundle_id", "app_version", "build_number", "build_id", "app_id").merge(
        "schema_version" => manifest.fetch("schema").fetch("schema_version"),
        "platform_sha" => manifest.fetch("platform_sha"), "manifest_sha256" => manifest_hash)
      raise Error, "Conflicting merged release entry for #{record.fetch('release_id')}" unless expected.all? { |key, value| release[key] == value }
      snapshot = registry.fetch("schemas").fetch(expected.fetch("schema_version"), nil)
      return false unless snapshot
      raise Error, "Merged snapshot does not match the published schema" unless snapshot.fetch("schema") == manifest.fetch("schema")
      true
    end

    def sync(release_id: nil, dry_run: false)
      failures = []
      records = published_records do |id, error|
        report_release_failure(failures, id, error)
      end
      # Retained publication proofs are obligations even after Apple stops
      # listing a version. Merge them before filtering a manual retry.
      @store.paths("releases/").each do |path|
        prior = @store.document(path)
        records << prior unless records.any? { |record| record["release_id"] == prior["release_id"] }
      end
      if release_id
        records = records.select { |record| record["release_id"] == release_id }
        raise Error, "Requested version is not a published App Store release after the baseline" if records.empty? && failures.empty?
      end
      registry = merged_registry
      records.each do |record|
        manifest, path, hash = evidence(record)
        id = record.fetch("release_id")
        if registered?(registry, record, manifest, hash)
          @out.puts "App Store #{record['app_version']} (#{record['build_number']}): freeze merged."
          unless dry_run
            @store.write({ "status/#{id}.json" => SchemaRelease.json({ release_id: id, state: "merged", platform_sha: manifest.fetch("platform_sha") }) },
                         message: "Record merged freeze for #{id}", mutable: ["status/#{id}.json"])
          end
          next
        end
        proof_path = "releases/#{id}.json"
        existing = @store.document(proof_path, optional: true)
        proof = record.merge("manifest_path" => path, "manifest_sha256" => hash, "observed_at" => Time.now.utc.iso8601)
        if existing
          %w[release_id app_id bundle_id app_version build_number build_id manifest_path manifest_sha256].each do |key|
            raise Error, "Published release evidence changed: #{key}" unless existing.fetch(key) == proof.fetch(key)
          end
          proof = existing
        end
        @out.puts "App Store #{record['app_version']} (#{record['build_number']}): freeze PR required for schema #{manifest['schema']['schema_version']}."
        next if dry_run
        commit = @store.write({ proof_path => SchemaRelease.json(proof) }, message: "Observe App Store release #{id}")
        @store.github.dispatch(id, commit)
        branch = "codex/freeze-swift-schema-v#{manifest['schema']['schema_version']}"
        @out.puts "Platform PR: https://github.com/#{PLATFORM_REPO}/pulls?q=#{URI.encode_www_form_component("is:pr head:#{branch}")}"
      rescue Error, KeyError, JSON::ParserError => error
        report_release_failure(failures, record["release_id"], error)
      end
      raise Error, "Some App Store releases still need attention: #{failures.join('; ')}" unless failures.empty?
    end

    def gate(platform_dir)
      registry = selected_registry(platform_dir)
      records = published_records
      @store.paths("releases/").each do |path|
        record = @store.document(path)
        records << record unless records.any? { |item| item["release_id"] == record["release_id"] }
      end
      merged = merged_registry
      records.each do |record|
        manifest, _path, hash = evidence(record)
        unless registered?(merged, record, manifest, hash)
          raise Error, "App Store #{record['app_version']} still needs a merged freeze in #{PLATFORM_REPO}:#{PLATFORM_BRANCH}. Run the App Store schema workflow and merge its PR into that branch first."
        end
        unless registered?(registry, record, manifest, hash)
          raise Error, "App Store #{record['app_version']} has a freeze in #{PLATFORM_REPO}:#{PLATFORM_BRANCH}, but it is missing from the selected Platform commit. Select a commit containing that freeze before uploading."
        end
        schema = registry.fetch("schemas").fetch(manifest.fetch("schema").fetch("schema_version"))
        fixture_path = File.expand_path(schema.fetch("fixture_path"), platform_dir)
        unless fixture_path.start_with?(File.expand_path(platform_dir) + "/") && File.file?(fixture_path) && Digest::SHA256.file(fixture_path).hexdigest == schema.fetch("fixture_sha256")
          raise Error, "Selected Platform checkout lacks the registered release fixture"
        end
      end
      @out.puts "Published schemas are reconciled in the selected Platform checkout."
    end

    private

    def report_release_failure(failures, id, error)
      failures << "#{id}: #{error.message}"
      @out.puts "::error::App Store release #{id} could not be reconciled: #{error.message}"
    end

    def parse_registry(bytes, location)
      registry = JSON.parse(bytes)
      unless registry.is_a?(Hash) && registry["format_version"] == 1 &&
             registry["schemas"].is_a?(Hash) && registry["releases"].is_a?(Hash)
        raise Error, "Unsupported or malformed schema registry at #{location}; restore the reviewed registry before releasing."
      end
      registry
    rescue JSON::ParserError
      raise Error, "Invalid JSON in schema registry at #{location}; restore the reviewed registry before releasing."
    end

    def selected_registry(platform_dir)
      sha, status = Open3.capture2("git", "-C", platform_dir, "rev-parse", "HEAD", err: File::NULL)
      checkout = "#{File.expand_path(platform_dir)} (#{status.success? ? sha.strip : 'unknown commit'})"
      missing = ([REGISTRY] + CAPTURE_FILES).reject { |path| File.file?(File.join(platform_dir, path)) }
      unless missing.empty?
        raise Error, "Selected Platform checkout #{checkout} lacks schema release support: #{missing.join(', ')}. Select a Platform commit containing the schema release pipeline."
      end
      parse_registry(File.read(File.join(platform_dir, REGISTRY)), checkout)
    end

    def merged_registry
      location = "#{PLATFORM_REPO}:#{PLATFORM_BRANCH}/#{REGISTRY}"
      bytes = @store.github.file(PLATFORM_REPO, REGISTRY, PLATFORM_BRANCH, optional: true)
      unless bytes
        raise Error, "Schema registry is unavailable at #{location}. Merge Platform schema release support first and verify SCHEMA_RELEASE_TOKEN access and organization approval."
      end
      parse_registry(bytes, location)
    rescue HTTPError => e
      hint = [401, 403, 404].include?(e.status) ?
        "Verify SCHEMA_RELEASE_TOKEN access and organization approval, then retry." :
        "GitHub is unavailable or rate-limited; retry the workflow after service recovers."
      raise Error, "Cannot read schema registry at #{location} (HTTP #{e.status}). #{hint}"
    end
  end

  def self.record_build(store, capture_dir, env)
    schema = validate_schema(JSON.parse(File.read(File.join(capture_dir, "schema.json"))))
    fixture = File.binread(File.join(capture_dir, "fixture.store"))
    raise Error, "Capture is not a SQLite store" unless fixture.start_with?("SQLite format 3\x00")
    digest = Digest::SHA256.hexdigest(fixture)
    manifest = {
      "format_version" => 1, "bundle_id" => env.fetch("BUNDLE_ID"), "app_version" => env.fetch("EFFECTIVE_VERSION"),
      "build_number" => env.fetch("BUILD_NUMBER"), "wallet_sha" => sha(env.fetch("WALLET_SHA")), "platform_sha" => sha(env.fetch("PLATFORM_SHA")),
      "workflow_run_id" => env.fetch("GITHUB_RUN_ID"), "workflow_run_attempt" => env.fetch("GITHUB_RUN_ATTEMPT"),
      "schema" => schema, "fixture_sha256" => digest, "fixture_path" => "stores/#{digest}.store",
      "toolchain" => JSON.parse(File.read(File.join(capture_dir, "toolchain.json")))
    }
    path = manifest_path(manifest["bundle_id"], manifest["app_version"], manifest["build_number"])
    store.github.retain_platform_source(manifest.fetch("platform_sha"))
    store.write({ path => json(manifest), manifest["fixture_path"] => fixture }, message: "Record schema evidence for #{manifest['app_version']} (#{manifest['build_number']})")
  end

  def self.bind_build(store, env)
    path = manifest_path(env.fetch("BUNDLE_ID"), env.fetch("EFFECTIVE_VERSION"), env.fetch("BUILD_NUMBER"))
    bytes = store.read(path)
    id = component(env.fetch("ASC_BUILD_ID"))
    store.write({ "apple-builds/#{id}.json" => json({ build_id: id, manifest_path: path, manifest_sha256: Digest::SHA256.hexdigest(bytes) }) },
                message: "Bind Apple build #{id} to its schema evidence")
  end

  def self.next_build(store, env)
    prefix = "builds/#{component(env.fetch('BUNDLE_ID'))}/#{component(env.fetch('EFFECTIVE_VERSION'))}/"
    reserved = store.paths(prefix).filter_map do |path|
      suffix = path.delete_prefix(prefix)
      suffix.split("/").first.to_i if suffix.match?(/\A[0-9]+\/manifest\.json\z/)
    end
    # A failed upload can leave immutable evidence for a number Apple has never
    # seen. Skip it, otherwise every retry would allocate the same blocked tuple.
    [Integer(env.fetch("MIN_BUILD_NUMBER")), (reserved.max || 0) + 1].max
  end

  def self.main(argv, env = ENV)
    options = {}
    parser = OptionParser.new do |opts|
      opts.on("--dry-run") { options[:dry_run] = true }
      opts.on("--release-id ID") { |value| options[:release_id] = component(value) }
      opts.on("--platform-dir DIR") { |value| options[:platform_dir] = value }
      opts.on("--capture-dir DIR") { |value| options[:capture_dir] = value }
    end
    command = argv.shift
    parser.parse!(argv)
    raise Error, "Unexpected positional arguments" unless argv.empty?
    store = Store.new(GitHub.new(env["SCHEMA_RELEASE_TOKEN"]))
    if command == "next-build"
      value = "build_number=#{next_build(store, env)}"
      puts value
      File.open(env.fetch("GITHUB_OUTPUT"), "a") { |file| file.puts(value) }
      return
    end
    if %w[record-build bind-build].include?(command)
      raise Error, "Use capture files for offline validation; this command writes evidence" if options[:dry_run]
      return command == "record-build" ? record_build(store, options.fetch(:capture_dir), env) : bind_build(store, env)
    end
    apple = AppStoreConnectRelease::Client.new(key_id: env.fetch("API_KEY_ID"), issuer_id: env.fetch("API_ISSUER_ID"), private_key_path: env.fetch("APP_STORE_CONNECT_API_KEY_PATH"))
    pipeline = Pipeline.new(store: store, apple: apple, bundle_id: env.fetch("BUNDLE_ID"))
    case command
    when "bootstrap" then pipeline.bootstrap(dry_run: options.fetch(:dry_run, false))
    when "sync" then pipeline.sync(release_id: options[:release_id], dry_run: options.fetch(:dry_run, false))
    when "gate" then pipeline.gate(options.fetch(:platform_dir))
    else raise Error, "Expected bootstrap, sync, gate, next-build, record-build or bind-build"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    SchemaRelease.main(ARGV)
  rescue SchemaRelease::Error, KeyError, JSON::ParserError, OptionParser::ParseError, Errno::ENOENT => e
    warn "::error::#{e.message}"
    exit 1
  end
end
