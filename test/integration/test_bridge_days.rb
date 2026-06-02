require File.expand_path(File.dirname(__FILE__)) + '/../test_helper'

# Sample of the Nager.Date long weekend API response for 2026 / HU.
# See https://date.nager.at/api/v3/LongWeekend/2026/HU
HU_2026_LONG_WEEKENDS = [
  { "startDate" => "2026-01-01", "endDate" => "2026-01-04", "dayCount" => 4, "needBridgeDay" => true,  "bridgeDays" => ["2026-01-02"] },
  { "startDate" => "2026-04-03", "endDate" => "2026-04-06", "dayCount" => 4, "needBridgeDay" => false, "bridgeDays" => [] },
  { "startDate" => "2026-12-25", "endDate" => "2026-12-27", "dayCount" => 3, "needBridgeDay" => false, "bridgeDays" => [] },
].freeze

class BridgeDaysTests < Test::Unit::TestCase
  def setup
    # Avoid hitting the network in tests.
    Holidays::BridgeDays.stubs(:fetch).returns(HU_2026_LONG_WEEKENDS)
  end

  def test_without_option_behaviour_is_unchanged
    holidays = Holidays.between(Date.civil(2026, 1, 1), Date.civil(2026, 1, 4), :hu)

    assert_equal [Date.civil(2026, 1, 1)], holidays.map { |h| h[:date] }
  end

  def test_bridge_days_are_returned_day_by_day_excluding_weekends
    # 2026-01-03 (Sat) and 2026-01-04 (Sun) are weekends -> already non-working.
    holidays = Holidays.between(Date.civil(2026, 1, 1), Date.civil(2026, 1, 4), :hu, :bridge_days)

    assert_equal(
      [Date.civil(2026, 1, 1), Date.civil(2026, 1, 2)],
      holidays.map { |h| h[:date] },
    )
  end

  def test_weekend_days_are_not_added_as_bridge_days
    holidays = Holidays.between(Date.civil(2026, 1, 1), Date.civil(2026, 1, 4), :hu, :bridge_days)

    assert_equal false, holidays.any? { |h| [0, 6].include?(h[:date].wday) }
  end

  def test_holiday_day_keeps_its_holiday_name
    holidays = Holidays.between(Date.civil(2026, 1, 1), Date.civil(2026, 1, 4), :hu, :bridge_days)
    jan_first = holidays.find { |h| h[:date] == Date.civil(2026, 1, 1) }

    assert_equal "Újév", jan_first[:name]
  end

  def test_pure_bridge_day_is_named_bridge_day
    holidays = Holidays.between(Date.civil(2026, 1, 1), Date.civil(2026, 1, 4), :hu, :bridge_days)
    bridge_day = holidays.find { |h| h[:date] == Date.civil(2026, 1, 2) }

    assert_equal "bridge-day", bridge_day[:name]
    assert_equal [:hu], bridge_day[:regions]
  end

  def test_dates_are_not_duplicated
    holidays = Holidays.between(Date.civil(2026, 1, 1), Date.civil(2026, 1, 4), :hu, :bridge_days)
    dates = holidays.map { |h| h[:date] }

    assert_equal dates.uniq, dates
  end

  def test_bridge_days_outside_the_range_are_excluded
    # 2026-01-03 is a Saturday, so only the Friday remains in range.
    holidays = Holidays.between(Date.civil(2026, 1, 2), Date.civil(2026, 1, 3), :hu, :bridge_days)

    assert_equal [Date.civil(2026, 1, 2)], holidays.map { |h| h[:date] }
  end

  def test_on_supports_the_option
    holidays = Holidays.on(Date.civil(2026, 1, 2), :hu, :bridge_days)

    assert_equal [Date.civil(2026, 1, 2)], holidays.map { |h| h[:date] }
    assert_equal "bridge-day", holidays.first[:name]
  end

  def test_production_detection_uses_environment_variables
    %w[RAILS_ENV RACK_ENV APP_ENV].each do |key|
      with_env(key, "production") do
        assert_equal true, Holidays::BridgeDays.send(:production?), "expected production? to be true for #{key}=production"
      end
      with_env(key, "staging") do
        assert_equal false, Holidays::BridgeDays.send(:production?), "expected production? to be false for #{key}=staging"
      end
    end
  end

  private

  def with_env(key, value)
    old = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = old
  end
end
