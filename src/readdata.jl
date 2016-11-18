#!/usr/bin/env julia

# Download and load trip data for September 2015.

datadir = "../data"
filename = "green_tripdata_2015-09.csv"
jldfilename = "data.jld"

rfname = joinpath(datadir, filename)
isdir(datadir) || mkdir(datadir)
isfile(rfname) || download("https://s3.amazonaws.com/nyc-tlc/trip+data/green_tripdata_2015-09.csv", rfname)

#Save parsed data frame to a JLD binary file in case we want to reuse it
rjldfname = joinpath(datadir, jldfilename)
if isfile(rjldfname)
    df = JLD.load(rjldfname, "df")
else
    df = CSV.read(rfname; weakrefstrings=false)
    JLD.save(rjldfname, "df", df, compress=true)
end

#################################er#######
#
# Report how many rows and columns of data
#

nc, nr = size(df)
info("Q1: Read in $nc columns and $nr rows")
