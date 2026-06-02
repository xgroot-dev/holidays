require 'date'

module Holidays
  # Augments a holiday ("vacation") result set with optional non-working days and
  # applies working-date overrides. Driven by three options that can be passed to
  # Holidays.on/Holidays.between:
  #
  #   :bridge_days
  #     Add the weekday "bridge" days of any long weekend (fetched from the
  #     Nager.Date API, see Holidays::BridgeDays), named "bridge-day".
  #
  #   weekend_as_vacation: [:saturday, :sunday] (or [] / bare :weekend_as_vacation)
  #     Add weekend days as vacations named "weekend". An empty list (or the bare
  #     symbol) means every weekend day; a subset such as [:saturday] limits it to
  #     those weekdays.
  #
  #   working_dates: ["2026-01-10", ...]
  #     Dates that must NOT be marked as a vacation/bridge/weekend even though they
  #     would otherwise qualify (e.g. Hungary's compensated working Saturdays).
  #     Any entry on these dates is removed from the result.
  #
  #   extra_vacation_dates: ["2026-12-24", ...]
  #     Dates to add manually as holidays named "vacation", for one-off / future
  #     state holidays that are not in the definitions yet (e.g. Hungary declaring
  #     2026-12-24 a public holiday). A real holiday on the same date keeps its own
  #     name.
  #
  # Dates are never duplicated. Precedence when a date qualifies for more than one
  # thing: a real holiday keeps its own name, then a manual vacation, then
  # bridge-day, then weekend.
  module Vacations
    BRIDGE_DAYS = :bridge_days
    WEEKEND_AS_VACATION = :weekend_as_vacation
    WORKING_DATES = :working_dates
    EXTRA_VACATION_DATES = :extra_vacation_dates

    OPTIONS = [BRIDGE_DAYS, WEEKEND_AS_VACATION, WORKING_DATES, EXTRA_VACATION_DATES].freeze

    WEEKEND_NAME = "weekend".freeze
    VACATION_NAME = "vacation".freeze

    WEEKDAY_NUMBERS = {
      :sunday => 0, :monday => 1, :tuesday => 2, :wednesday => 3,
      :thursday => 4, :friday => 5, :saturday => 6,
    }.freeze
    DEFAULT_WEEKEND_DAYS = [:saturday, :sunday].freeze

    NON_REGION_OPTIONS = [:observed, :informal, :any].freeze

    class << self
      # Splits the augmentation options out of the raw option list.
      #
      # Returns [settings, remaining_options]. When no augmentation option is
      # present, settings is nil and the original options are returned untouched
      # (so normal lookups and caching are unaffected).
      def extract_settings(options)
        settings = {}
        remaining = []

        options.flatten.each do |option|
          case option
          when Hash
            option.each { |key, value| store_setting(settings, key, value) }
          when BRIDGE_DAYS
            settings[:bridge_days] = true
          when WEEKEND_AS_VACATION
            settings[:weekend_as_vacation] = weekday_numbers(DEFAULT_WEEKEND_DAYS)
          else
            remaining << option
          end
        end

        return nil, options if settings.empty?

        [settings, remaining]
      end

      # holidays:   array of {:date, :name, :regions} hashes (the "vacations")
      # start_date: queried range start (Date)
      # end_date:   queried range end (Date)
      # options:    the cleaned region/observed/informal options
      # settings:   the hash returned by #extract_settings
      #
      # Returns a new array sorted by date, day by day.
      def call(holidays, start_date, end_date, options, settings)
        regions = region_symbols(options)

        result = holidays.dup
        seen = {}
        result.each { |h| seen[h[:date]] = true }

        if extra_vacation_dates = settings[:extra_vacation_dates]
          extra_vacation_dates.each do |date|
            next if date < start_date || date > end_date

            add(result, seen, date, VACATION_NAME, regions)
          end
        end

        if settings[:bridge_days]
          BridgeDays.weekdays_between(regions, start_date, end_date).each do |date|
            add(result, seen, date, BridgeDays::NAME, regions)
          end
        end

        if weekend_days = settings[:weekend_as_vacation]
          (start_date..end_date).each do |date|
            next unless weekend_days.include?(date.wday)

            add(result, seen, date, WEEKEND_NAME, regions)
          end
        end

        if working_dates = settings[:working_dates]
          result.reject! { |h| working_dates.include?(h[:date]) }
        end

        result.sort_by { |h| h[:date] }
      end

      private

      def add(result, seen, date, name, regions)
        return if seen[date] # already present -> keep the existing (higher priority) name

        seen[date] = true
        result << { :date => date, :name => name, :regions => regions }
      end

      def store_setting(settings, key, value)
        case key
        when BRIDGE_DAYS
          settings[:bridge_days] = value.nil? ? true : value
        when WEEKEND_AS_VACATION
          days = Array(value)
          days = DEFAULT_WEEKEND_DAYS if days.empty?
          settings[:weekend_as_vacation] = weekday_numbers(days)
        when WORKING_DATES
          settings[:working_dates] = Array(value).map { |d| to_date(d) }
        when EXTRA_VACATION_DATES
          settings[:extra_vacation_dates] = Array(value).map { |d| to_date(d) }
        end
      end

      def weekday_numbers(days)
        days.map { |d| WEEKDAY_NUMBERS.fetch(d.to_sym) }
      end

      def to_date(value)
        value.is_a?(Date) ? value : Date.parse(value.to_s)
      end

      def region_symbols(options)
        options.flatten.reject { |o| NON_REGION_OPTIONS.include?(o) }
      end
    end
  end
end
