require File.expand_path(File.dirname(__FILE__)) + '/../test_helper'

# Sample of the Nager.Date long weekend API response for 2026 / HU.
# See https://date.nager.at/api/v3/LongWeekend/2026/HU
HU_2026_LONG_WEEKENDS_FULL = [
  { "startDate" => "2026-01-01", "endDate" => "2026-01-04" },
  { "startDate" => "2026-04-03", "endDate" => "2026-04-06" },
  { "startDate" => "2026-05-01", "endDate" => "2026-05-03" },
  { "startDate" => "2026-05-23", "endDate" => "2026-05-25" },
  { "startDate" => "2026-08-20", "endDate" => "2026-08-23" },
  { "startDate" => "2026-10-23", "endDate" => "2026-10-25" },
  { "startDate" => "2026-12-25", "endDate" => "2026-12-27" },
].freeze

class VacationsTests < Test::Unit::TestCase
  def setup
    Holidays::BridgeDays.stubs(:fetch).returns(HU_2026_LONG_WEEKENDS_FULL)
  end

  def names_by_date(holidays)
    holidays.each_with_object({}) { |h, acc| acc[h[:date]] = h[:name] }
  end

  # --- weekend_as_vacation ----------------------------------------------------

  def test_weekend_as_vacation_empty_list_adds_every_weekend_day
    holidays = Holidays.between(Date.civil(2026, 1, 1), Date.civil(2026, 1, 11), :hu, :weekend_as_vacation => [])
    names = names_by_date(holidays)

    # Sat/Sun within the range are all "weekend"
    assert_equal "weekend", names[Date.civil(2026, 1, 3)]  # Sat
    assert_equal "weekend", names[Date.civil(2026, 1, 4)]  # Sun
    assert_equal "weekend", names[Date.civil(2026, 1, 10)] # Sat
    assert_equal "weekend", names[Date.civil(2026, 1, 11)] # Sun
    assert_equal "Újév", names[Date.civil(2026, 1, 1)]     # holiday name preserved
  end

  def test_weekend_as_vacation_saturday_only
    holidays = Holidays.between(Date.civil(2026, 1, 1), Date.civil(2026, 1, 11), :hu, :weekend_as_vacation => [:saturday])
    dates = holidays.map { |h| h[:date] }

    assert_includes dates, Date.civil(2026, 1, 3)   # Sat -> added
    assert_includes dates, Date.civil(2026, 1, 10)  # Sat -> added
    assert_not_includes dates, Date.civil(2026, 1, 4)  # Sun -> not added
    assert_not_includes dates, Date.civil(2026, 1, 11) # Sun -> not added
  end

  # --- working_dates ----------------------------------------------------------

  def test_working_dates_remove_the_date_entirely
    holidays = Holidays.between(
      Date.civil(2026, 1, 1), Date.civil(2026, 1, 11),
      :hu, :weekend_as_vacation => [:saturday], :working_dates => ["2026-01-10"],
    )
    dates = holidays.map { |h| h[:date] }

    assert_includes dates, Date.civil(2026, 1, 3)      # normal working Saturday -> weekend
    assert_not_includes dates, Date.civil(2026, 1, 10) # working Saturday -> removed
  end

  # --- extra_vacation_dates ---------------------------------------------------

  def test_extra_vacation_dates_are_added_as_holidays
    # 2026-12-24 is not a HU holiday in the definitions; add it manually.
    holidays = Holidays.between(
      Date.civil(2026, 12, 24), Date.civil(2026, 12, 24),
      :hu, :extra_vacation_dates => ["2026-12-24"],
    )

    assert_equal 1, holidays.size
    assert_equal Date.civil(2026, 12, 24), holidays.first[:date]
    assert_equal "vacation", holidays.first[:name]
    assert_equal [:hu], holidays.first[:regions]
  end

  def test_extra_vacation_dates_do_not_override_a_real_holiday
    holidays = Holidays.between(
      Date.civil(2026, 12, 25), Date.civil(2026, 12, 25),
      :hu, :extra_vacation_dates => ["2026-12-25"],
    )

    assert_equal "Karácsony", holidays.first[:name]
  end

  def test_extra_vacation_dates_outside_the_range_are_ignored
    holidays = Holidays.between(
      Date.civil(2026, 12, 1), Date.civil(2026, 12, 20),
      :hu, :extra_vacation_dates => ["2026-12-24"],
    )

    assert_not_includes holidays.map { |h| h[:date] }, Date.civil(2026, 12, 24)
  end

  # --- the full scenario from the request ------------------------------------

  def test_bridge_days_plus_saturdays_minus_working_dates
    working = ["2026-01-10", "2026-08-08", "2026-12-12"]
    holidays = Holidays.between(
      Date.civil(2026, 1, 1), Date.civil(2026, 12, 31),
      :hu, :bridge_days,
      :weekend_as_vacation => [:saturday],
      :working_dates => working,
    )
    names = names_by_date(holidays)
    dates = holidays.map { |h| h[:date] }

    # Vacations (real holidays) are present with their own names.
    assert_equal "Újév", names[Date.civil(2026, 1, 1)]
    assert_equal "Karácsony", names[Date.civil(2026, 12, 25)]

    # Bridge days (weekdays) are present.
    assert_equal "bridge-day", names[Date.civil(2026, 1, 2)]   # Fri
    assert_equal "bridge-day", names[Date.civil(2026, 8, 21)]  # Fri

    # Saturdays are present as "weekend"...
    assert_equal "weekend", names[Date.civil(2026, 1, 3)]
    assert_equal "weekend", names[Date.civil(2026, 1, 17)]

    # ...except the three compensated working Saturdays.
    working.each { |d| assert_not_includes dates, Date.parse(d) }

    # A holiday that happens to fall on a Saturday keeps its holiday name.
    assert_equal "Karácsony", names[Date.civil(2026, 12, 26)] # Sat

    # Sundays are NOT added (only :saturday requested), unless they are holidays.
    assert_not_includes dates, Date.civil(2026, 1, 4)  # plain Sunday
    assert_includes dates, Date.civil(2026, 3, 15)     # holiday on a Sunday

    # No duplicate dates.
    assert_equal dates.uniq, dates
  end
end
