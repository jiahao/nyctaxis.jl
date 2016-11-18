#!/usr/bin/env julia

# Report mean and median trip distance grouped by hour of day.

# Here we use the pickup time
df[:Hour] = map(x->Int(Dates.Hour(x)), df, :lpep_pickup_datetime)
df_byhour = by(df, :Hour) do group
    DataFrame(  meantripdist=  mean(group, :Trip_distance),
              mediantripdist=median(group, :Trip_distance))
end
display(df_byhour)

#Make a plot
bar(df_byhour, :Hour, [:meantripdist, :mediantripdist],
    xlabel = "Hour of day", ylabel = "Trip distance (mi.)")
png(joinpath(plotdir, "q3-hourofday"))
info("Q3: Summary statistics saved to q3-hourofday.png")

########################################

#Get a rough sense of identifying trips that originate or terminate at one of
#the NYC area airports.

#Note data dictionary at:
# http://www.nyc.gov/html/tlc/downloads/pdf/data_dictionary_trip_records_green.pdf


#For reference we also use a shapefile describing NYC itself
#Shapefile coordinates in lat-lon and internal coordinates
# Source: http://www1.nyc.gov/assets/planning/download/pdf/data-maps/open-data/nybb_metadata.pdf?ver=16c
llw = -74.257159 #lat-lon west
lle = -73.699215
lln = 40.915568
lls = 40.495992

bbw = 913174.999355 #bounding box west
bbe = 1067382.508423
bbs = 120121.779352
bbn = 272844.293640

#Look at the three major airports
for (aircode, airn, airw, airs, aire, xmax, ymax) in (
        ("JFK", 40.664673, -73.810947, 40.639527, -73.775498, 45, 180),
        ("EWR", 40.706581, -74.192315, 40.670655, -74.151288, 60, 200),
        ("LGA", 40.782098, -73.887313, 40.766823, -73.858302, 35, 160)
    )

#Predicate for whether a latlon coordinate is in the airport box
isinairport(lat, lon) = (airs < lat < airn) && (airw < lon < aire)
isinairport(coord) = isinairport(coord...)

#Find subset whose dropoff coordinates are inside the box
dropoffs_at_airport = map(isinairport, zip(df, :Dropoff_latitude, :Dropoff_longitude))
df_dropoffs = df[dropoffs_at_airport, :]

#Find subset whose pickup coordinates are inside the box
pickups_at_airport = map(isinairport, zip(df, :Pickup_latitude, :Pickup_longitude))
df_pickups = df[pickups_at_airport, :]

#filter out spuriously low fares
df_dropoffs = filter(x -> x≥2.5, df_dropoffs, :Fare_amount)
df_pickups  = filter(x -> x≥2.5, df_pickups,  :Fare_amount)

#filter out spuriously high fare
df_dropoffs = filter(x -> x<450, df_dropoffs, :Fare_amount)

#filter out legitimate outlier
df_pickups = filter(x -> x>-74.37, df_pickups, :Dropoff_longitude)

#filter out trips shorter than 1 mile
df_dropoffs = filter(x -> x≥1, df_dropoffs, :Trip_distance)
df_pickups  = filter(x -> x≥1, df_pickups,  :Trip_distance)

#filter out trips shorter than 1 minute
df_dropoffs[:Duration] = map(x->Int(x)÷1000, (Array(df_dropoffs[:Lpep_dropoff_datetime]) -
Array(df_dropoffs[:lpep_pickup_datetime])))
df_pickups[:Duration] = map(x->Int(x)÷1000, (Array(df_pickups[:Lpep_dropoff_datetime]) -
Array(df_pickups[:lpep_pickup_datetime])))

df_dropoffs = filter(x -> x≥60, df_dropoffs, :Duration)
df_pickups  = filter(x -> x≥60, df_pickups,  :Duration)

#Analyze fares by pickup and dropoff, and by payment by credit card (Payment_type = 1) or cash (2)
df_dropoffs_cc   = filter(x -> x==1, df_dropoffs, :Payment_type)
df_dropoffs_cash = filter(x -> x==2, df_dropoffs, :Payment_type)
df_pickups_cc    = filter(x -> x==1, df_pickups,  :Payment_type)
df_pickups_cash  = filter(x -> x==2, df_pickups,  :Payment_type)

for (group, typ, paytyp) in (
        (df_dropoffs_cc, "dropoffs", "credit card"),
        (df_dropoffs_cash, "dropoffs", "cash"),
        (df_pickups_cc, "pickups", "credit card"),
        (df_pickups_cash, "pickups", "cash")
    )
    info("Number of $paytyp $typ at $aircode: $(size(group, 1))")
    if size(group, 1) == 0
        continue
    end
    info("Mean fare: \$$(round(mean(group, :Fare_amount), 2))")
    info("Median fare: \$$(median(group, :Fare_amount))")
    info("Mean distance: $(mean(group, :Trip_distance))")
    info("Median distance: $(median(group, :Trip_distance))")
end

#Plot the minimum metered fare
x = 0:60
y = 2.5 .+ 2.5*x


plot(x, y, c = :grey, label = "Minimum metered fare", xlims = (0, 60),
    ylims = (0, 200),
    xlabel = "Trip distance (mi.)", ylabel = "Total amount (\$)")
plot!(x, 1.8y, c = :grey, label = "1.8x min. metered fare")

scatter!(df_dropoffs_cc, :Trip_distance, :Total_amount,
    label = "Dropoffs/Credit (N = $(size(df_dropoffs_cc, 1)))", color = :blue,
    markerstrokewidth = 0, markershape = :dtriangle, alpha=0.5)
scatter!(df_dropoffs_cash, :Trip_distance, :Total_amount,
    label = "Dropoffs/Cash (N = $(size(df_dropoffs_cash, 1)))", color = :blue,
    markerstrokewidth = 1, markershape = :dtriangle, alpha=0.6)
scatter!(df_pickups_cc, :Trip_distance, :Total_amount,
    label = "Pickups/Credit (N = $(size(df_pickups_cc, 1)))", color = :red,
    markerstrokewidth = 0, alpha=0.6, markershape = :utriangle)
scatter!(df_pickups_cash, :Trip_distance, :Total_amount,
    label = "Pickups/Cash (N = $(size(df_pickups_cash, 1)))", color = :red,
    markerstrokewidth = 1, alpha=0.6, markershape = :utriangle)


png(joinpath(plotdir, "q3-$aircode-cost-vs-distance"))
info("Cost vs distance plot saved to q3-$aircode-cost-vs-distance.png")


#######################################
# Look at structure of fares
for code = 1:5

surcharge = code==3 ? 17.50 : 0.0 #Newark surcharge
plot(x, y + surcharge, c = :grey, label = "Minimum metered fare", xlims = (0, 45),
    ylims = (0, 180),
    xlabel = "Trip distance (mi.)", ylabel = "Total amount (\$)")
plot!(x, 1.8*(y + surcharge), c = :grey, label = "1.8x min. metered fare")
z = filter(x->x==code, df_dropoffs_cc, :RateCodeID)
scatter!(z, :Trip_distance, :Total_amount,
    label = "Dropoffs/Credit (N=$(size(z, 1)))", color = :lightblue,
    markerstrokewidth = 0, alpha=1, markershape = :dtriangle)
z = filter(x->x==code, df_dropoffs_cash, :RateCodeID)
scatter!(z, :Trip_distance, :Total_amount,
    label = "Dropoffs/Cash (N=$(size(z, 1)))", color = :blue,
    markerstrokewidth = 0, alpha=1, markershape = :dtriangle)
z = filter(x->x==code, df_pickups_cc, :RateCodeID)
scatter!(z, :Trip_distance, :Total_amount,
        label = "Pickups/Credit (N=$(size(z, 1)))", color = :pink,
        markerstrokewidth = 0, alpha=0.6, markershape = :utriangle)
z = filter(x->x==code, df_pickups_cash, :RateCodeID)
scatter!(z, :Trip_distance, :Total_amount,
        label = "Pickups/Cash (N=$(size(z, 1)))", color = :red,
        markerstrokewidth = 0, alpha=0.6, markershape = :utriangle)
png(joinpath(plotdir, "q3-$aircode-cost-vs-distance-code$code"))
info("Breakdown saved to q3-$aircode-cost-vs-distance-code$code.png")
end


#######################################
# Plot map

#Plot points for pickup locations, but filter out coordinates (0, 0) first
function filterandscale(df, lon, lat)
    x = Array(df[lon])
    y = Array(df[lat])
    z = !((x.==0) ∩ (y.==0))
    x = x[z]
    y = y[z]
    return scaletobox(x, y)
end

function scaletobox(x, y)
    x = (x - llw)/(lle - llw)*(bbe - bbw) + bbw
    y = (y - lls)/(lln - lls)*(bbn - bbs) + bbs
    return x, y
end

####################################################
#Read in shapefile for boroughs of NYC and plot them

if !isfile(joinpath(datadir, "nybb_16c", "nybb.shp"))
    download("http://www1.nyc.gov/assets/planning/download/zip/data-maps/open-data/nybb_16c.zip",
             joinpath(datadir, "nybb_16c.zip"))
    run(Cmd(`unzip nybb_16c.zip`, dir=datadir))
end

nyc = open(joinpath(datadir, "nybb_16c", "nybb.shp")) do f
    read(f, Shapefile.Handle)
end


################
#Start plotting

shapeplot(nyc.shapes, c=:lightgrey)

#Plot the box we used to represent airport
bbairw, bbairn = scaletobox(airw, airn)
bbaire, bbairs = scaletobox(aire, airs)
airport = Polygon(Rect(bbn,bbw,bbs,bbe), Int32[0],
	[Point(bbairw, bbairn), Point(bbaire, bbairn), Point(bbaire, bbairs), Point(bbairw, bbairs)])
shapeplot!(airport, c=:green, linewidth=0.0)

#Plot dropoffs and pickups
scatter!(filterandscale(df_dropoffs, :Pickup_longitude, :Pickup_latitude)...,
        color = :blue, markershape = :utriangle,
        markerstrokewidth=0.0, alpha = 0.3)
scatter!(filterandscale(df_pickups, :Dropoff_longitude, :Dropoff_latitude)...,
        color = :red, markershape = :dtriangle,
        markerstrokewidth=0.0, alpha = 0.3)
shapeplot!(nyc.shapes, c=nothing, title = "Green cab trips to (blue) and from (red) $aircode, Sep. 2015")

png(joinpath(plotdir, "q3-$aircode-map"))
info("Map of green cab trips to (blue) and from (red) $aircode saved to q3-$aircode-map.png")

end #Loop over airports
