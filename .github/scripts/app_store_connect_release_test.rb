# frozen_string_literal: true

require "minitest/autorun"
require_relative "app_store_connect_release"

class AppStoreConnectReleaseTest < Minitest::Test
  def resolve(requested:, testflight: [], production: [])
    AppStoreConnectRelease.resolve_effective_version(
      requested: requested,
      testflight_versions: testflight,
      production_versions: production
    )
  end

  def test_requested_version_is_used_as_given
    result = resolve(requested: "9.2.0", testflight: ["9.1.0"], production: ["9.0.1"])

    assert_equal "9.2.0", result.fetch(:effective)
    assert_equal "9.1.0", result.fetch(:latest_testflight)
    assert_equal "9.0.1", result.fetch(:latest_production)
  end

  def test_version_below_testflight_but_above_production_is_allowed
    result = resolve(requested: "9.0.5", testflight: ["9.1.0"], production: ["9.0.1"])

    assert_equal "9.0.5", result.fetch(:effective)
  end

  def test_version_below_live_app_store_fails
    error = assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "9.0.1", testflight: [], production: ["9.1.0"])
    end

    assert_match "not above the live App Store version 9.1.0", error.message
  end

  def test_version_equal_to_live_app_store_fails
    assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "9.1.0", testflight: [], production: ["9.1"])
    end
  end

  def test_first_release_needs_no_existing_versions
    result = resolve(requested: "1.0.0")

    assert_equal "1.0.0", result.fetch(:effective)
    assert_nil result.fetch(:latest_testflight)
    assert_nil result.fetch(:latest_production)
  end

  def test_existing_train_spelling_wins_for_equivalent_version
    result = resolve(requested: "9.1.0", testflight: ["9.1"], production: [])

    assert_equal "9.1", result.fetch(:effective)
  end

  def test_exact_train_spelling_beats_equivalent_train
    result = resolve(requested: "9.1.0", testflight: %w[9.1 9.1.0], production: [])

    assert_equal "9.1.0", result.fetch(:effective)
  end

  def test_invalid_version_fails
    assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "v9.1", testflight: ["9.0.0"])
    end
  end

  def test_next_build_number_starts_at_one
    assert_equal 1, AppStoreConnectRelease.next_build_number([])
  end

  def test_next_build_number_uses_highest_existing_number
    assert_equal 8, AppStoreConnectRelease.next_build_number(%w[1 7 3])
  end

  def test_non_integer_build_number_fails
    assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease.next_build_number(["1.2"])
    end
  end

  def test_release_channel_validation
    assert_equal "internal-only", AppStoreConnectRelease.validate_release_channel("internal-only")
    assert_equal "internal", AppStoreConnectRelease.validate_release_channel("internal")
    assert_equal "external", AppStoreConnectRelease.validate_release_channel("external")
    assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease.validate_release_channel("upload-only")
    end
  end

  def test_external_group_validation
    assert_equal "Public Beta", AppStoreConnectRelease.validate_external_group("Public Beta", ["Public Beta"])
    assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease.validate_external_group("Missing", ["Public Beta"])
    end
  end

  def test_live_app_store_version_accepts_new_state_attribute
    attributes = { "appVersionState" => "READY_FOR_DISTRIBUTION" }

    assert AppStoreConnectRelease.live_app_store_version?(attributes)
  end

  def test_live_app_store_version_accepts_deprecated_state_attribute
    attributes = { "appStoreState" => "READY_FOR_SALE" }

    assert AppStoreConnectRelease.live_app_store_version?(attributes)
  end

  def test_current_state_takes_precedence_over_deprecated_state
    attributes = {
      "appVersionState" => "IN_REVIEW",
      "appStoreState" => "READY_FOR_SALE"
    }

    refute AppStoreConnectRelease.live_app_store_version?(attributes)
    refute AppStoreConnectRelease.live_app_store_version?({ "appVersionState" => "READY_FOR_SALE" }),
           "A legacy-only spelling is not a recognized current publication state"
  end

  def test_unknown_current_state_blocks_observation_but_not_known_publication_lookup
    client = fake_client
    client.define_singleton_method(:get_all) do |_url|
      [{ "id" => "new", "attributes" => { "versionString" => "9.2.0",
        "appVersionState" => "FUTURE_APPLE_STATE", "appStoreState" => "READY_FOR_SALE" } }]
    end
    [:published_versions, :latest_published_version].each do |method|
      error = assert_raises(AppStoreConnectRelease::Error) { client.public_send(method, "app") }
      assert_includes error.message, "Unknown appVersionState"
      assert_includes error.message, "9.2.0"
    end
    assert_empty client.production_versions("app"), "Do not trust the deprecated live state over an unknown current one"
  end

  def test_unknown_history_before_accepted_baseline_does_not_block_observation_or_bootstrap
    client = fake_client
    client.define_singleton_method(:get_all) do |_url|
      [
        { "id" => "old", "attributes" => { "versionString" => "6.0.0", "appVersionState" => "OLD_UNKNOWN_STATE" } },
        { "id" => "new", "attributes" => { "versionString" => "9.1.0", "appVersionState" => "READY_FOR_DISTRIBUTION" } }
      ]
    end
    assert_equal ["new"], client.published_versions("app", after_version: "9.0.0").map { |row| row["id"] }
    assert_equal "new", client.latest_published_version("app")["id"]
  end

  def test_unknown_newer_state_blocks_bootstrap_even_with_an_older_known_publication
    client = fake_client
    client.define_singleton_method(:get_all) do |_url|
      [
        { "id" => "old", "attributes" => { "versionString" => "9.1.0", "appVersionState" => "READY_FOR_DISTRIBUTION" } },
        { "id" => "new", "attributes" => { "versionString" => "9.2.0", "appVersionState" => "FUTURE_APPLE_STATE" } }
      ]
    end
    assert_raises(AppStoreConnectRelease::Error) { client.latest_published_version("app") }
  end

  def test_paginator_collects_all_pages
    pages = {
      "first" => { "data" => [1], "links" => { "next" => "second" } },
      "second" => { "data" => [2], "links" => { "next" => nil } }
    }

    records = AppStoreConnectRelease::Paginator.collect("first") { |url| pages.fetch(url) }

    assert_equal [1, 2], records
  end

  def test_paginator_has_a_page_limit
    assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease::Paginator.collect("loop", max_pages: 2) do
        { "data" => [], "links" => { "next" => "loop" } }
      end
    end
  end

  def test_api_errors_are_reported
    error = assert_raises(AppStoreConnectRelease::Error) do
      AppStoreConnectRelease::Client.parse_response(500, '{"errors":[]}')
    end

    assert_match "HTTP 500", error.message
  end

  def test_rate_limits_and_server_errors_are_transient
    assert_raises(AppStoreConnectRelease::TransientError) do
      AppStoreConnectRelease::Client.parse_response(429, '{"errors":[]}')
    end
    assert_raises(AppStoreConnectRelease::TransientError) do
      AppStoreConnectRelease::Client.parse_response(503, '{"errors":[]}')
    end
  end

  def fake_client
    AppStoreConnectRelease::Client.new(key_id: "test", issuer_id: "test", private_key_path: "unused")
  end

  def test_published_versions_excludes_review_and_beta_states
    client = fake_client
    client.define_singleton_method(:get_all) do |_url|
      %w[READY_FOR_DISTRIBUTION IN_REVIEW PENDING_DEVELOPER_RELEASE].map do |state|
        { "id" => state, "attributes" => { "appVersionState" => state, "versionString" => "9.1.0" } }
      end
    end
    assert_equal ["READY_FOR_DISTRIBUTION"], client.published_versions("app").map { |row| row["id"] }
    assert_equal ["9.1.0"], client.production_versions("app")
  end

  def test_superseded_release_remains_part_of_published_history
    assert AppStoreConnectRelease.published_app_store_version?({ "appVersionState" => "REPLACED_WITH_NEW_VERSION" })
    assert AppStoreConnectRelease.published_app_store_version?({ "appStoreState" => "REPLACED_WITH_NEW_VERSION" })
    refute AppStoreConnectRelease.published_app_store_version?({ "appVersionState" => "IN_REVIEW", "appStoreState" => "REPLACED_WITH_NEW_VERSION" })
  end

  def test_current_version_state_remains_authoritative_after_removal_from_sale
    %w[DEVELOPER_REMOVED_FROM_SALE REMOVED_FROM_SALE].each do |legacy|
      %w[READY_FOR_DISTRIBUTION REPLACED_WITH_NEW_VERSION].each do |current|
        assert AppStoreConnectRelease.published_app_store_version?({
          "appVersionState" => current, "appStoreState" => legacy
        })
      end
      refute AppStoreConnectRelease.published_app_store_version?({
        "appVersionState" => "PENDING_DEVELOPER_RELEASE", "appStoreState" => legacy
      })
    end
  end

  def test_legacy_removal_alone_stops_publication_reads_instead_of_guessing
    %w[DEVELOPER_REMOVED_FROM_SALE REMOVED_FROM_SALE].each do |legacy|
      client = fake_client
      client.define_singleton_method(:get_all) do |_url|
        [{ "id" => "old-version", "attributes" => { "appStoreState" => legacy, "versionString" => "9.1.0" } }]
      end
      error = assert_raises(AppStoreConnectRelease::Error) { client.published_versions("app") }
      assert_includes error.message, "Ambiguous publication history"
      assert_includes error.message, "9.1.0"
      assert_includes error.message, legacy
    end
  end

  def test_internal_only_version_resolution_is_not_blocked_by_ambiguous_freeze_history
    client = fake_client
    client.define_singleton_method(:get_all) do |_url|
      [
        { "attributes" => { "appStoreState" => "REMOVED_FROM_SALE", "versionString" => "8.0.0" } },
        { "attributes" => { "appVersionState" => "READY_FOR_DISTRIBUTION", "versionString" => "9.0.0" } }
      ]
    end
    client.define_singleton_method(:testflight_versions) { |_app| [] }
    command = AppStoreConnectRelease::Command.new([], env: { "RELEASE_CHANNEL" => "internal-only", "REQUESTED_VERSION" => "9.1.0" })
    command.define_singleton_method(:write_outputs) { |values| values }
    outputs = command.send(:resolve_version, client, "app")
    assert_equal "9.1.0", outputs.fetch("effective_version")
    assert_equal "9.0.0", outputs.fetch("latest_production_version")
    assert_raises(AppStoreConnectRelease::Error) { client.published_versions("app") }
  end

  def test_internal_only_version_resolution_survives_unknown_current_states
    client = fake_client
    client.define_singleton_method(:get_all) do |_url|
      [
        { "id" => "unknown", "attributes" => { "appVersionState" => "FUTURE_APPLE_STATE", "appStoreState" => "READY_FOR_SALE", "versionString" => "9.2.0" } },
        { "id" => "known", "attributes" => { "appVersionState" => "READY_FOR_DISTRIBUTION", "versionString" => "9.0.0" } }
      ]
    end
    client.define_singleton_method(:testflight_versions) { |_app| [] }
    command = AppStoreConnectRelease::Command.new([], env: { "RELEASE_CHANNEL" => "internal-only", "REQUESTED_VERSION" => "9.1.0" })
    command.define_singleton_method(:write_outputs) { |values| values }
    outputs = command.send(:resolve_version, client, "app")
    assert_equal "9.1.0", outputs.fetch("effective_version")
    assert_equal "9.0.0", outputs.fetch("latest_production_version")
    assert_raises(AppStoreConnectRelease::Error) { client.published_versions("app") }
    assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "9.0.0", production: client.production_versions("app"))
    end
  end

  def test_internal_only_ignores_malformed_unpublished_rows_without_weakening_publication_checks
    client = fake_client
    irrelevant = [nil, [], { "attributes" => nil }, { "attributes" => [] },
                  { "attributes" => "invalid" }, { "attributes" => {} },
                  { "attributes" => { "appVersionState" => "PREPARE_FOR_SUBMISSION" } },
                  { "attributes" => { "appVersionState" => "IN_REVIEW", "versionString" => "invalid" } },
                  { "attributes" => { "appVersionState" => "FUTURE_STATE", "appStoreState" => "READY_FOR_SALE" } }]
    client.define_singleton_method(:app_store_versions) do |_app|
      irrelevant + [{ "attributes" => { "appVersionState" => "READY_FOR_DISTRIBUTION", "versionString" => "9.0.0" } }]
    end
    client.define_singleton_method(:testflight_versions) { |_app| [] }
    command = AppStoreConnectRelease::Command.new([], env: { "RELEASE_CHANNEL" => "internal-only", "REQUESTED_VERSION" => "9.1.0" })
    command.define_singleton_method(:write_outputs) { |values| values }
    outputs = command.send(:resolve_version, client, "app")
    assert_equal "9.1.0", outputs.fetch("effective_version")
    assert_equal "9.0.0", outputs.fetch("latest_production_version")
    assert_raises(AppStoreConnectRelease::Error) { client.published_versions("app") }
    assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "9.0.0", production: client.production_versions("app"))
    end
  end

  def test_malformed_known_publications_still_block_testflight_version_resolution
    client = fake_client
    %w[READY_FOR_DISTRIBUTION REPLACED_WITH_NEW_VERSION].each do |state|
      [nil, "invalid"].each do |number|
        attributes = { "appVersionState" => state }
        attributes["versionString"] = number if number
        client.define_singleton_method(:app_store_versions) { |_app| [{ "attributes" => attributes }] }
        assert_raises(AppStoreConnectRelease::Error) { client.production_versions("app") }
      end
    end
  end

  def test_publication_validation_collects_bad_records_and_continues
    client = fake_client
    records = [nil, [], { "id" => "nil-attributes", "attributes" => nil },
               { "id" => "array-attributes", "attributes" => [] },
               { "id" => "string-attributes", "attributes" => "invalid" },
               { "id" => "missing-version", "attributes" => {} },
               { "id" => "bad-version", "attributes" => { "versionString" => "not-a-version" } },
               { "id" => "unknown", "attributes" => { "versionString" => "9.1.0", "appVersionState" => "FUTURE_STATE" } },
               { "id" => "valid", "attributes" => { "versionString" => "9.2.0", "appVersionState" => "READY_FOR_DISTRIBUTION" } }]
    client.define_singleton_method(:app_store_versions) { |_app| records }
    failures = []
    rows = client.published_versions("app", after_version: "9.0.0") { |id, error| failures << [id, error] }
    assert_equal ["valid"], rows.map { |row| row["id"] }
    assert_equal records.length - 1, failures.length
    assert failures.all? { |_, error| error.is_a?(AppStoreConnectRelease::Error) }
    assert_equal "nil-attributes", failures[2].first
    assert_includes failures[2].last.message, "expected an attributes object"
    assert_raises(AppStoreConnectRelease::Error) { client.published_versions("app", after_version: "9.0.0") }
    assert_raises(AppStoreConnectRelease::Error) { client.latest_published_version("app") }
  end

  def test_testflight_guard_still_includes_known_superseded_publications
    client = fake_client
    client.define_singleton_method(:get_all) do |_url|
      [{ "attributes" => { "appVersionState" => "REPLACED_WITH_NEW_VERSION", "versionString" => "9.1.0" } }]
    end
    assert_raises(AppStoreConnectRelease::Error) do
      resolve(requested: "9.1.0", production: client.production_versions("app"))
    end
  end

  def test_reads_exact_build_relationship_and_rejects_missing_build
    client = fake_client
    requested = []
    client.define_singleton_method(:get_json) do |url|
      requested << url
      { "data" => { "id" => "build21" } }
    end
    assert_equal "build21", client.version_build("version-id")["id"]
    assert_equal "https://api.appstoreconnect.apple.com/v1/appStoreVersions/version-id/build", requested.first
    [{ "data" => nil }, {}].each do |response|
      client.define_singleton_method(:get_json) { |_url| response }
      error = assert_raises(AppStoreConnectRelease::Error) { client.version_build("version-id") }
      assert_includes error.message, "Published App Store version version-id has no associated build"
    end
  end

  def test_read_retries_transient_errors_without_network
    client = fake_client
    calls = 0
    client.define_singleton_method(:perform_get) do |_uri|
      calls += 1
      raise AppStoreConnectRelease::TransientError, "rate limited" if calls < 3
      { "data" => [] }
    end
    client.define_singleton_method(:sleep) { |_seconds| nil }
    assert_equal({ "data" => [] }, client.send(:get_json, "https://api.appstoreconnect.apple.com/v1/apps"))
    assert_equal 3, calls
  end

  def test_pagination_cannot_send_apple_credentials_to_another_host
    assert_raises(AppStoreConnectRelease::Error) { fake_client.send(:get_json, "https://example.com/v1/apps") }
  end

  def test_transport_read_errors_have_four_attempts_and_a_safe_final_message
    [SocketError, IOError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
     Errno::ECONNRESET, OpenSSL::SSL::SSLError].each do |type|
      client = fake_client
      calls, delays = 0, []
      client.define_singleton_method(:perform_get) do |_uri|
        calls += 1
        raise type, "private-test-token"
      end
      client.define_singleton_method(:sleep) { |seconds| delays << seconds }
      error = assert_raises(AppStoreConnectRelease::TransientError) do
        client.send(:get_json, "https://api.appstoreconnect.apple.com/v1/apps")
      end
      assert_equal 4, calls
      assert_equal [1, 2, 4], delays
      assert_includes error.message, "failed after 4 attempts"
      refute_includes error.message, "private-test-token"
    end
  end

  def test_http_read_errors_stop_after_four_attempts
    client = fake_client
    calls, delays = 0, []
    client.define_singleton_method(:perform_get) do |_uri|
      calls += 1
      AppStoreConnectRelease::Client.parse_response(503, '{"errors":[]}')
    end
    client.define_singleton_method(:sleep) { |seconds| delays << seconds }
    error = assert_raises(AppStoreConnectRelease::TransientError) do
      client.send(:get_json, "https://api.appstoreconnect.apple.com/v1/apps")
    end
    assert_equal 4, calls
    assert_equal [1, 2, 4], delays
    assert_includes error.message, "HTTP 503"
  end

  def test_http_client_does_not_add_hidden_retries
    client = fake_client
    client.define_singleton_method(:authorization_token) { "private-test-token" }
    http = Struct.new(:max_retries).new
    http.define_singleton_method(:request) do |_request|
      raise "Net::HTTP retry budget was not disabled" unless max_retries == 0
      Struct.new(:code, :body).new("200", '{"data":[]}')
    end
    original_start = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*_args, **_options, &block| block.call(http) }
    assert_equal({ "data" => [] }, client.send(:get_json, "https://api.appstoreconnect.apple.com/v1/apps"))
  ensure
    Net::HTTP.define_singleton_method(:start, original_start) if original_start
  end
end
