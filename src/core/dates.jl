# Day numbers ("serial values") and Julia dates and times.
#
# Spreadsheets hold dates as numbers of days since day 0, and times as fractions of a day.
# Excel counts from 1899-12-30 in its 1900 system (taking 1900 to be a leap year, so its
# day numbers below 61 are off by one from the plain calendar) or from 1904-01-01. ODF
# stores dates as ISO text, but a date used as a number (in a formula, or under a number
# format) counts from the document's `table:null-date`, 1899-12-30 by default, on the
# plain Gregorian calendar.
#
# The Excel functions are copied from XLSX.jl 0.13.4 (src/cell.jl),
# MIT License, Copyright (c) 2018-2026 Felipe Noronha Tavares and other contributors.
# Changes: XLSXError → SheetCoreError. The epoch functions are new.

const EXCEL_DATE_OFFSET_1904 = 695056
const EXCEL_DATE_OFFSET_1900 = 693594
const NANOSECONDS_PER_DAY    = Int64(86_400) * Int64(1_000_000_000)

# Converts Excel number to Time.
# x must be in [0, 1), where 1 represents one full day.
# The decimal part of a floating point number represents the time fraction of a day.
function excel_value_to_time(x::Float64)::Dates.Time
    0.0 <= x < 1.0 || throw(SheetCoreError("A value must be in [0, 1) to be converted to time. Got $x"))
    return Dates.Time(Dates.Nanosecond(round(Int64, x * NANOSECONDS_PER_DAY)))
end

time_to_excel_value(x::Dates.Time)::Float64 = Dates.value(x) / NANOSECONDS_PER_DAY

# Converts Excel number to Date.
function excel_value_to_date(x::Integer, is1904::Bool)::Dates.Date
    offset = is1904 ? EXCEL_DATE_OFFSET_1904 : EXCEL_DATE_OFFSET_1900
    return Dates.Date(Dates.rata2datetime(x + offset))
end

function date_to_excel_value(date::Dates.Date, is1904::Bool)::Int64
    offset = is1904 ? EXCEL_DATE_OFFSET_1904 : EXCEL_DATE_OFFSET_1900
    return Dates.datetime2rata(date) - offset
end

# Converts Excel number to DateTime.
# The integer part represents the Date, the decimal part the Time.
function excel_value_to_datetime(x::Float64, is1904::Bool)::Dates.DateTime
    x >= 0 || throw(SheetCoreError("Cannot have a datetime value < 0. Got $x"))
    dt_part = trunc(Int64, x)
    # Round to nearest second to absorb float precision drift. Added as a period, not
    # a `Time`, so a value that rounds up to midnight moves on to the next day.
    secs = round(Int64, (x - dt_part) * 86_400)
    return Dates.DateTime(excel_value_to_date(dt_part, is1904)) + Dates.Second(secs)
end

function datetime_to_excel_value(dt::Dates.DateTime, is1904::Bool)::Float64
    date_part = date_to_excel_value(Dates.Date(dt), is1904)
    time_part = Dates.value(Dates.Time(dt)) / NANOSECONDS_PER_DAY  # integer nanoseconds / const
    return date_part + time_part
end

#
# Day numbers from any epoch (ODF `table:null-date`), on the plain Gregorian calendar.
#

"""
    DEFAULT_NULL_DATE

ODF's default `table:null-date`: day 0 is 1899-12-30. From 1900-03-01 onwards the day
numbers equal Excel's 1900-system ones.
"""
const DEFAULT_NULL_DATE = Dates.Date(1899, 12, 30)

"""
    date_to_serial(d::Date, epoch::Date = DEFAULT_NULL_DATE) -> Int64
    serial_to_date(n::Integer, epoch::Date = DEFAULT_NULL_DATE) -> Date

The number of days from `epoch` to `d`, and back. Negative before the epoch.
"""
date_to_serial(d::Dates.Date, epoch::Dates.Date = DEFAULT_NULL_DATE)::Int64 =
    Dates.value(d - epoch)
serial_to_date(n::Integer, epoch::Dates.Date = DEFAULT_NULL_DATE)::Dates.Date =
    epoch + Dates.Day(n)

"""
    datetime_to_serial(dt::DateTime, epoch::Date = DEFAULT_NULL_DATE) -> Float64
    serial_to_datetime(x::Real, epoch::Date = DEFAULT_NULL_DATE) -> DateTime

A date and time as days from `epoch` with the time as a fraction of a day, and back.
The time is rounded to the nearest millisecond (DateTime's resolution); a value that
rounds up to midnight moves on to the next day.
"""
function datetime_to_serial(dt::Dates.DateTime, epoch::Dates.Date = DEFAULT_NULL_DATE)::Float64
    ms = Dates.value(dt - Dates.DateTime(epoch))          # milliseconds, may be negative
    return ms / 86_400_000
end

function serial_to_datetime(x::Real, epoch::Dates.Date = DEFAULT_NULL_DATE)::Dates.DateTime
    isfinite(x) || throw(SheetCoreError("Cannot convert $x to a date and time."))
    return Dates.DateTime(epoch) + Dates.Millisecond(round(Int64, Float64(x) * 86_400_000))
end
