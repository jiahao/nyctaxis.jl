#!/usr/bin/env julia

# This file loads the necessary Julia packages and custom commands used in the
# analysis

# If a given package, e.g. CSV.jl is not installed, run
#
#    Pkg.add("CSV")
#
using CSV
using DataFrames
using Distributions
using GLM
using JLD
using StatsBase
using Shapefile
using Plots
using PlotRecipes
using StatPlots

import Shapefile: Polygon, Rect, Point

###############################################################################
# This section defines directories to put data files and plots

datadir = "../data"
plotdir = "../plot"

jldfilename = "data.jld" #JLD file to save results to

#Create directories if necessary
isdir(datadir) || mkdir(datadir)
isdir(plotdir) || mkdir(plotdir)

###############################################################################
# This section defines customized extensions to existing base and plotting
# functions that I found convenient while working with the data

############################################################
# Customized data frame handling syntax for base functions #
############################################################

Base.quantile(df::AbstractDataFrame, fld::Symbol, args...; kwargs...) =
    quantile(Array(df[fld]), args...; kwargs...)
Base.filter(f::Function, df::AbstractDataFrame, fld::Symbol) = begin
     x = map(f, df, fld)
     size(x, 1)==0 ? df[1:0, :] : df[x, :]
end
Base.map(f::Function, df::AbstractDataFrame, fld::Symbol) = map(f, Array(df[fld]))
Base.mean(df::AbstractDataFrame, fld::Symbol) = mean(Array(df[fld]))
Base.median(df::AbstractDataFrame, fld::Symbol) = median(Array(df[fld]))

Base.zip(df::AbstractDataFrame, fld1::Symbol, fld2::Symbol) = zip(Array(df[fld1]), Array(df[fld2]))
Base.sum(df::AbstractDataFrame, fld::Symbol) = sum(Array(df[fld]))
Base.std(df::AbstractDataFrame, fld::Symbol) = std(Array(df[fld]))
StatsBase.fit{T<:Distribution}(d::Type{T}, df::AbstractDataFrame, fld::Symbol) =
    fit(d, Array(df[fld]))
##################################
# Customized plotting extensions #
##################################

#Syntax sugar for handling NullableArrays
Plots.histogram(A::NullableArray, args...; kwargs...) =
    histogram(Array(A), args...; kwargs...)
Plots.bar(A::NullableArray, B::NullableArray, args...; kwargs...) =
    bar(Array(A), Array(B), args...; kwargs...)
Plots.bar!(A::NullableArray, B::NullableArray, args...; kwargs...) =
    bar!(Array(A), Array(B), args...; kwargs...)
Plots.scatter(A::NullableArray, B::NullableArray, args...; kwargs...) =
    scatter(Array(A), Array(B), args...; kwargs...)
Plots.scatter!(A::NullableArray, B::NullableArray, args...; kwargs...) =
    scatter!(Array(A), Array(B), args...; kwargs...)
Plots.plot(A::NullableArray, B::NullableArray, args...; kwargs...) =
        plot(Array(A), Array(B), args...; kwargs...)
Plots.plot!(A::NullableArray, B::NullableArray, args...; kwargs...) =
    plot!(Array(A), Array(B), args...; kwargs...)

#Syntax sugar for handling fields in a data frame
Plots.histogram(df::AbstractDataFrame, fld::Symbol, args...; kwargs...) =
    histogram(df[fld], args...; kwargs...)
Plots.bar(df::AbstractDataFrame, xfld::Symbol, yfld::Symbol, args...; kwargs...) =
    bar(df[xfld], df[yfld], args...; kwargs...)
Plots.bar!(df::AbstractDataFrame, xfld::Symbol, yfld::Symbol, args...; kwargs...) =
    bar!(df[xfld], df[yfld], args...; kwargs...)
Plots.scatter(df::AbstractDataFrame, xfld::Symbol, yfld::Symbol, args...; kwargs...) =
    scatter(df[xfld], df[yfld], args...; kwargs...)
Plots.scatter!(df::AbstractDataFrame, xfld::Symbol, yfld::Symbol, args...; kwargs...) =
    scatter!(df[xfld], df[yfld], args...; kwargs...)
Plots.plot(df::AbstractDataFrame, xfld::Symbol, yfld::Symbol, args...; kwargs...) =
        plot(df[xfld], df[yfld], args...; kwargs...)
Plots.plot!(df::AbstractDataFrame, xfld::Symbol, yfld::Symbol, args...; kwargs...) =
        plot!(df[xfld], df[yfld], args...; kwargs...)

"""
Plot probability density function (pdf) of a Distribution

Takes the usual keyword arguments of Plots.jl, but also allows specification of:

- scale, a scaling factor (normalization constant)
- bins, the number of points to plot the pdf over
- xlims, the lower and upper limits of the domain to plot the pdf over
"""
function pdfplot!(d::Distribution; scale = 1.0, xlims = nothing, bins = 100, kwargs...)
    xmin, xmax = xlims
    xs = linspace(xmin, xmax, nbins)
    binsize = scale*(xs[2]-xs[1])
    ys = map(_->binsize*pdf(d, _), xs)
    ys[isnan(ys)] = 0 #Fix bug with support of some distributions like LogNormal
                      #Ref: https://github.com/JuliaStats/Distributions.jl/issues/456
    plot!(xs, ys; kwargs...)
end

"""
Plots a stacked bar chart of various columns of the data frame df

- df, a data frame
- xfld, the field to use as the x axis
- yflds, an array of fields of plot along the y axes

Automatically generates labels which are the field names
"""
function Plots.bar(df::AbstractDataFrame, xfld::Symbol, yflds::Vector{Symbol}, args...; kwargs...)
    first = true
    for yfld in yflds
        if first
            bar(df, xfld, yfld, label=string(yfld), args...; kwargs...)
            first = !first
        else
            bar!(df, xfld, yfld, label=string(yfld))
        end
    end
end
