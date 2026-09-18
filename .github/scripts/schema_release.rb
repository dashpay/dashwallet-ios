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
      raise Error, "SCHEMA_RELEASE_TOKEN is missing" if token.nil? || token.empty?
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
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 45) { |http| http.request(request) }
        status = response.code.to_i
        return nil if optional && status == 404
        unless status.between?(200, 299)
          raise HTTPError.new(status, "GitHub #{method.upcase} #{uri.path} returned HTTP #{status}")
        end
        response.body.to_s.empty? ? {} : JSON.parse(response.body)
      rescue HTTPError => e
        raise unless method == "get" && (e.status == 429 || e.status >= 500) && attempts < 4
        sleep(2**(attempts - 1))
        retry
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
          raise unless [409, 422].include?(e.status) && head != parent
        end
      end
      raise Error, "Release-data branch stayed busy after five atomic update attempts"
    end
  end

  class Pipeline
    def initialize(store:, apple:, bundle_id:, output: $stdout)
      @store, @apple, @bundle, @out = store, apple, SchemaRelease.component(bundle_id), output
    end

    def bootstrap(dry_run: false)
      raise Error, "Baseline already exists; it must never be moved forward" if @store.document("baseline.json", optional: true)
      app = @apple.find_app(@bundle)
      versions = @apple.published_versions(app.fetch("id"))
      newest = versions.max_by { |version| AppStoreConnectRelease::MarketingVersion.new(version.fetch("attributes").fetch("versionString")) }
      raise Error, "No published App Store version to accept as V1" unless newest
      baseline = { format_version: 1, bundle_id: @bundle, app_id: app.fetch("id"),
                   max_app_version: newest.fetch("attributes").fetch("versionString"),
                   release_id: newest.fetch("id"), schema_version: "1.0.0", accepted_at: Time.now.utc.iso8601 }
      @out.puts "Accepting existing App Store version #{baseline[:max_app_version]} as the V1 baseline."
      @store.write({ "baseline.json" => SchemaRelease.json(baseline) }, message: "Initialize SwiftData release baseline") unless dry_run
    end

    def published_records
      baseline = @store.document("baseline.json")
      raise Error, "Baseline belongs to a different app" unless baseline.fetch("bundle_id") == @bundle
      app = @apple.find_app(@bundle)
      raise Error, "App Store app identifier changed" unless baseline.fetch("app_id") == app.fetch("id")
      versions = @apple.published_versions(app.fetch("id"))
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
      records = published_records
      if release_id
        records = records.select { |record| record["release_id"] == release_id }
        raise Error, "Requested version is not a published App Store release after the baseline" if records.empty?
      end
      # Observed releases remain obligations even if later removed from sale.
      unless release_id
        @store.paths("releases/").each do |path|
          prior = @store.document(path)
          records << prior unless records.any? { |record| record["release_id"] == prior["release_id"] }
        end
      end
      registry_bytes = @store.github.file(PLATFORM_REPO, REGISTRY, PLATFORM_BRANCH)
      registry = JSON.parse(registry_bytes)
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
      end
    end

    def gate(platform_dir)
      registry = JSON.parse(File.read(File.join(platform_dir, REGISTRY)))
      records = published_records
      @store.paths("releases/").each do |path|
        record = @store.document(path)
        records << record unless records.any? { |item| item["release_id"] == record["release_id"] }
      end
      merged = JSON.parse(@store.github.file(PLATFORM_REPO, REGISTRY, PLATFORM_BRANCH))
      records.each do |record|
        manifest, _path, hash = evidence(record)
        unless registered?(merged, record, manifest, hash) && registered?(registry, record, manifest, hash)
          raise Error, "App Store #{record['app_version']} still needs a merged freeze present in the selected Platform commit. Run the App Store schema workflow and merge its PR first."
        end
        schema = registry.fetch("schemas").fetch(manifest.fetch("schema").fetch("schema_version"))
        fixture_path = File.expand_path(schema.fetch("fixture_path"), platform_dir)
        unless fixture_path.start_with?(File.expand_path(platform_dir) + "/") && File.file?(fixture_path) && Digest::SHA256.file(fixture_path).hexdigest == schema.fetch("fixture_sha256")
          raise Error, "Selected Platform checkout lacks the registered release fixture"
        end
      end
      @out.puts "Published schemas are reconciled in the selected Platform checkout."
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
    store = Store.new(GitHub.new(env.fetch("SCHEMA_RELEASE_TOKEN")))
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
