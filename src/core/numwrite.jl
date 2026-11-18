# Writing numbers without making a string for each: `print` allocates for every float and
# integer, and Julia has no public way to format one without.
#
# Adapted from XLSX.jl 0.13.4 (src/save.jl `_format_digits!`, `_write_short_float`, and the
# integer `_write_number`), MIT License, Copyright (c) 2018-2026 Felipe Noronha Tavares and
# other contributors. Changes: the digit buffer is an argument instead of a field of
# XLSX.jl's row writer; `write_float` and `write_integer` wrap them with `print` as the
# fallback.

"""
    _format_digits!(buf::Vector{UInt8}, u::Unsigned) -> Int

The decimal digits of `u` at the end of `buf`: they are `buf[i+1:end]` for the `i` returned.
"""
function _format_digits!(buf::Vector{UInt8}, u::Unsigned)::Int
    i = length(buf)
    while true
        buf[i] = UInt8('0') + UInt8(u % 10)
        u ÷= 10
        i -= 1
        u == 0 && break
    end
    return i
end

"""
    write_integer(io, buf, n::Integer; mindigits=1)

Write `n` in decimal (zero-padded to `mindigits`), using `buf` (64 bytes or more) for the
digits.
"""
function write_integer(io::IO, buf::Vector{UInt8}, n::Integer; mindigits::Int = 1)
    neg = n < 0
    i = _format_digits!(buf, neg ? unsigned(-(Int128(n))) : unsigned(n))
    while length(buf) - i < mindigits
        buf[i] = UInt8('0'); i -= 1
    end
    neg && (buf[i] = UInt8('-'); i -= 1)
    GC.@preserve buf unsafe_write(io, pointer(buf, i + 1), length(buf) - i)
    return nothing
end

const _EXACT_POW10 = ntuple(i -> 10.0^(i - 1), 23)   # 1e0 to 1e22, each exact in a Float64

"""
    write_float(io, buf, x::Float64)

Write `x` as `print` does (its shortest decimal that reads back as `x`), without making a
string when that decimal has at most 15 digits; otherwise through `print`.
"""
write_float(io::IO, buf::Vector{UInt8}, x::Float64) = (_write_short_float(io, buf, x) || print(io, x); nothing)

# Write `x` if its shortest decimal has at most 15 digits, and return whether it did.
#
# For `d` = 0, 1, ..., take `m = round(|x| * 10^d)`. When `m < 10^15` and `d <= 22`,
# both `m` and `10^d` are exact floats, so IEEE division rounds `m / 10^d` correctly:
# if that is `|x|`, the decimal `m`e-`d` reads back as `x`. The first such `d` gives the
# shortest decimal. It is the one `print` writes, as that is the shortest that reads
# back and, with 15 digits or fewer, no other decimal of as many digits is as close.
# Neither is it missed: a decimal of `d` places that reads back as `x` is within
# 10^d × ulp(x)/2 < 0.12 of `|x| * 10^d`, and the product's own error is smaller than
# 0.12, so it rounds to that decimal.
#
# `print` writes 1e-4 <= |x| < 1e6 as `123.45` and the rest as `1.2345e6`.
function _write_short_float(io::IO, buf::Vector{UInt8}, x::Float64)::Bool
    isfinite(x) || return false
    a = abs(x)
    if a == 0
        write(io, signbit(x) ? "-0.0" : "0.0")
        return true
    end
    a >= 1e15 && return false
    m, d = UInt64(0), 0
    while true
        d > 22 && return false
        p = _EXACT_POW10[d + 1]
        y = a * p
        y >= 1e15 && return false
        m = unsafe_trunc(UInt64, round(y))
        Float64(m) / p == a && break
        d += 1
    end

    i = _format_digits!(buf, m)
    n = length(buf) - i                    # the number of digits
    signbit(x) && write(io, UInt8('-'))
    GC.@preserve buf begin
        digits = pointer(buf, i + 1)
        if 1e-4 <= a < 1e6
            if d == 0
                unsafe_write(io, digits, n)
                write(io, ".0")
            elseif n > d                   # 123.45
                unsafe_write(io, digits, n - d)
                write(io, UInt8('.'))
                unsafe_write(io, digits + (n - d), d)
            else                           # 0.0012
                write(io, "0.")
                for _ in 1:(d - n)
                    write(io, UInt8('0'))
                end
                unsafe_write(io, digits, n)
            end
        else
            e10 = n - 1 - d
            while n > 1 && buf[i + n] == UInt8('0')   # 1.5e14, not 1.50000000000000e14
                n -= 1
            end
            unsafe_write(io, digits, 1)
            write(io, UInt8('.'))
            n == 1 ? write(io, UInt8('0')) : unsafe_write(io, digits + 1, n - 1)
            write(io, UInt8('e'))
            e10 < 0 && write(io, UInt8('-'))
            j = _format_digits!(buf, unsigned(abs(e10)))   # the mantissa is written: reuse `buf`
            unsafe_write(io, pointer(buf, j + 1), length(buf) - j)
        end
    end
    return true
end
