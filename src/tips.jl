#!/usr/bin/env julia

# Build a derived variable for tip as a percentage of the total fare.

tip_pct = 100*Array(df[:Tip_amount])./Array(df[:Total_amount])
tip_pct[isnan(tip_pct)] = 0 #Correct for division by 0 - in this case, treat it as 0% tip
df[:Tip_pct] = tip_pct

histogram(tip_pct, bins=100, xlabel = "Tip %", ylabel = "Count",
    leg = nothing, title = "Histogram of tip % (N = $(size(df, 1)))")
png(joinpath(plotdir, "q4-histogram-tippct"))
info("Q4: Histogram of tip percentages saved in q4-histogram-tippct.png")

###############################################################################

# Build a predictive model for tip as a percentage of the total fare.

# The cash tips and credit card tips are significantly different. According to
# the data dictionary, cash tips may not be recorded in the system.


info("Breakdown of tip % for cash payments")
dfcash = filter(x-> x==2, df, :Payment_type)
display(by(dfcash, :Tip_pct, nrow))
# 4×2 DataFrames.DataFrame
# │ Row │ Tip_pct │ x1     │
# ├─────┼─────────┼────────┤
# │ 1   │ -0.0    │ 205    │
# │ 2   │ 0.0     │ 783492 │
# │ 3   │ 16.6667 │ 1      │
# │ 4   │ 97.2132 │ 1      │

# We predict that the tip is 0 if payment is made in cash.

#######################################
# Now look at credit cards

#Payment_type = 1 for credit cards
dfcc = filter(x-> x==1, df, :Payment_type)
ncc = size(dfcc, 1)
info("Isolating $ncc trips paid for by card")

scatter(dfcc, :Fare_amount, :Tip_pct, alpha=0.01, xlims=(0, 40), ylims=(0, 100),
 markerstrokewidth=0, xlabel = "Fare amount", ylabel = "Tip %", label = "")
png(joinpath(plotdir, "q4-lowfares"))

#Select only fares which exceed the minimum flag-down rate of $2.50
#Ref: http://www.nyc.gov/html/tlc/html/passenger/taxicab_rate.shtml
dfcc = filter(x -> x > 2.50, dfcc, :Fare_amount)
nbad = ncc - size(dfcc, 1)
ncc = size(dfcc, 1)
info("Removed $nbad reported trips at the minimum fare")

#Filter out fares with very large tips
# dfcc = filter(x -> x < 40, dfcc, :Tip_pct)
# nbad = ncc - size(dfcc, 1)
# ncc = size(dfcc, 1)
# info("Removed $nbad reported trips that tipped more than 40%")

info("Analyzing $ncc trips")

histogram(dfcc, :Tip_pct, bins=120, title = "Tip % for credit payments (N=$ncc)",
    leg=nothing, xlims=(0, 100), ylabel = "Count")
png(joinpath(plotdir, "q4-histogram-tippct-cc"))
info("Q4: Histogram of tip percentages for credit card payments saved in q4-histogram-tippct-cc.png")

#######################################
# Add more derived variables

dfcc[:DayOfWeek] = map(Dates.dayofweek, dfcc, :lpep_pickup_datetime)

hourofday(x::DateTime) = Int(Dates.Hour(x)) + Int(Dates.Minute(x))/60 +
    Int(Dates.Second(x))/3_600 + Int(Dates.Millisecond(x))/3_600_000
hourofday_bymin(x::DateTime) = Int(Dates.Hour(x)) + Int(Dates.Minute(x))/60

# Hour: hour of day as a continuous variable from [0, 24)
dfcc[:Hour] = map(hourofday, dfcc, :lpep_pickup_datetime)
dfcc[:HourMin] = map(hourofday_bymin, dfcc, :lpep_pickup_datetime)

dow(x::DateTime) = Int(Dates.dayofweek(x))%7 + Int(Dates.Hour(x))/24
dfcc[:Dow] = map(dow, dfcc, :lpep_pickup_datetime)

#######################################

# Look at temporal variation by day of week and time of day
perdow = by(dfcc, :Dow) do group
    mean(group, :Tip_pct)
end

p=fft(Array(perdow[:x1]))
bar(abs(p[2:80]),
    label="", xlabel = "Fourier modes (1/week)",
    ylabel = "Magnitude (%)",
    title = "Power spectrum of tip variation over the week")
q = zeros(p)
q[1] = p[1]
nmodes = 0
for i = 2:168÷2
    if abs(p[i]) > 5
        nmodes  += 1
        q[    i] = p[i]
        q[end-i+1] = p[end-i+1]
    end
end
bar!(abs(q[2:80]), label= "")
png(joinpath(plotdir, "q4-tippct-fourier"))
info("Modes of temporal variation saved to q4-tippct-fourier.png")

q2 = ifft(q)
r = real(q2)
@assert sum(imag(q2)) < 1e-12

scatter(perdow, :Dow, :x1, xlabel = "Day of week", ylabel = "Mean tip %", label="Raw", xlims=(0, 7), markerstrokewidth=0)
plot!(Array(perdow[:Dow]), r, linewidth=3, label = "$nmodes modes")
png(joinpath(plotdir, "q4-tippct-byhour"))
info("Temporal variation saved to q4-tippct-byhour.png")

#Construct our filtered temporal variation
function fourierfilter(df::AbstractDataFrame, fld::Symbol, q)
    ncc = size(df, 1)
    N = size(q, 1)
    per = fill(real(q[1])/N, ncc)
    t0 = Array(df[fld])
    for i = 1:ncc
        t = t0[i]
        for j = 2:N÷2
            a, b = reim(q[j])
            ϕ = j*2t/7
            per[i] += 2/N*(a*cospi(ϕ)-b*sinpi(ϕ))
        end
    end
    per
end
dfcc[:Periodic] = fourierfilter(dfcc, :Dow, q)

#######################################
# Look at geographic variations

function groupbycoord(dfcc::AbstractDataFrame, xfld, yfld, zfld;
    xmin = -74.07,
    xmax = -73.75,
    ymin = 40.56,
    ymax = 40.89, n=100, thresh=20)

    dx = (xmax-xmin)/n
    dy = (ymax-ymin)/n
    #Keep aspect ratio 1:1, so use larger of dx, dy
    dx = dy = max(dx, dy)
    nx = ceil(Int, (xmax-xmin)/dx)
    ny = ceil(Int, (xmax-xmin)/dy)

    x = Array(dfcc[xfld])
    y = Array(dfcc[yfld])
    z = Array(dfcc[zfld])
    cnt = Dict()
    for i=1:ncc
        xi = x[i]
        yi = y[i]
        if xi == 0 || yi == 0 #Impute with mean and drop from bin
            dfcc[i, xfld] = (xmax+xmin)/2
            dfcc[i, yfld] = (ymax+ymin)/2
            continue
        end

        xbin = 1 + round(Int, (xi - xmin)/dx)
        ybin = 1 + round(Int, (yi - ymin)/dy)

        if !(1 <= xbin <= nx) || !(1 <= ybin <= ny) continue end

        cnt[(xbin, ybin)] = push!(get(cnt, (xbin, ybin), Float64[]), z[i])
    end

    #Drop all rare events from analysis
    for (k, v) in cnt
        if length(v) <= thresh
            delete!(cnt, k)
        end
    end

    means = zeros(nx, ny)
    for (k, v) in cnt
        means[k...] = mean(v)
    end
    return means
end

heatmap(groupbycoord(dfcc, :Pickup_longitude, :Pickup_latitude, :Tip_pct)', title = "Mean tip % by pickup location")
png(joinpath(plotdir, "q4-tippct-bypickup.png"))

heatmap(groupbycoord(dfcc, :Pickup_longitude, :Pickup_latitude, :Tip_pct)', title = "Mean tip % by dropoff location")
png(joinpath(plotdir, "q4-tippct-bydropoff.png"))

#######################################

# Define some helper functions for computing residuals and root mean square metric
StatsBase.residuals(model::DataFrames.DataFrameRegressionModel, df::AbstractDataFrame, fld::Symbol) = Array(predict(model, df) - df[fld])
rms(a) = √(sumabs2(a)/size(a, 1))

# Collect together the fitting of a least squares linear model
function makelm(f::Formula, df::AbstractDataFrame)
    model = lm(f, df)
    info("Model summary:")
    display(model)

    #Compute and check residuals
    res = residuals(model, df, f.lhs)
    histogram(res, bins=120, leg = nothing,
              title = "Residuals (rms = $(round(rms(res), 2)), r² = $(round(r²(model), 3)))")
    return model
end

#######################################

#Construct a series of increasingly complicated linear least squares regression models

#result: rms = 7.82, r² = 0.005
model0 = makelm(Tip_pct ~ Fare_amount, dfcc)
png(joinpath(plotdir, "q4-res-linearmodel0"))
info("Residuals for linear model 0 saved in q4-res-linearmodel0.png")

#result: rms = 7.81, r² = 0.007
#Not too surprising; we expect these variables to be highly correlated
model1 = makelm(Tip_pct ~ Fare_amount + Trip_distance, dfcc)
png(joinpath(plotdir, "q4-res-linearmodel1"))
info("Residuals for linear model 1 saved in q4-res-linearmodel1.png")

#result: rms = 7.82, r² = 0.006
#Tolls add little explanatory power
model2 = makelm(Tip_pct ~ Fare_amount + Tolls_amount, dfcc)
png(joinpath(plotdir, "q4-res-linearmodel2"))
info("Residuals for linear model 2 saved in q4-res-linearmodel2.png")

#result: rms = 7.82, r² = 0.006
#Seasonal variations are mostly absent
model3 = makelm(Tip_pct ~ Fare_amount + Periodic + DayOfWeek, dfcc)
png(joinpath(plotdir, "q4-res-linearmodel3"))
info("Residuals for linear model 3 saved in q4-res-linearmodel3.png")

#result: rms = 7.74, r² = 0.024
#Strangely, a weak correlation with geography
model4 = makelm(Tip_pct ~ Fare_amount + Pickup_longitude + Pickup_latitude + Dropoff_longitude + Dropoff_latitude, dfcc)
png(joinpath(plotdir, "q4-res-linearmodel4"))
info("Residuals for linear model 4 saved in q4-res-linearmodel4.png")

#result: rms = 7.73, r² = 0.027
model5 = makelm(Tip_pct ~ Fare_amount + Trip_distance + Tolls_amount + Periodic +
  Pickup_longitude + Pickup_latitude + Dropoff_longitude + Dropoff_latitude, dfcc)
png(joinpath(plotdir, "q4-res-linearmodel5"))
info("Residuals for linear model 5 saved in q4-res-linearmodel5.png")

#######################################
# Try a categorical strategy
# Going back to the histogram of tips, it looks like there are four outlying values.
#
# It turns out that NYC cabs have default tips of 20%, 25% or 30%
# when translated in to % of total fare, the corresponding percentages are 16.66...%, 20% and 20.3769...%
#Also, it looks like many people tip 0% (!)

#Attempt to build a 5-way classifier using the one-vs-all method
#Category 1: People who tip 0%
#Category 2: People who tip 20% (16.67% of total amount)
#Category 3: People who tip 25% (20.00% of total amount)
#Category 4: People who tip 30% (23.07% of total amount)
#Category 5: People who tip another amount

#Add category labels to the data
dfcc[:cat1] = map(Int, Array(dfcc[:Tip_pct]) .== 0.00)
info("$(round(100*sum(dfcc, :cat1)/ncc, 1))% of trips tipped 0%")

#Allow some slack for roundoff error
dfcc[:cat2] = map(Int, abs(Array(dfcc[:Tip_pct]) - 2000//120) .< 0.5)
info("$(round(100*sum(dfcc, :cat2)/ncc, 1))% of trips tipped 20%")

dfcc[:cat3] = map(Int, abs(Array(dfcc[:Tip_pct]) - 2500//125) .< 0.5)
info("$(round(100*sum(dfcc, :cat3)/ncc, 1))% of trips tipped 25%")

dfcc[:cat4] = map(Int, abs(Array(dfcc[:Tip_pct]) - 3000//130) .< 0.5)
info("$(round(100*sum(dfcc, :cat4)/ncc, 1))% of trips tipped 30%")

dfcc[:cat5] = 1 - Array(dfcc[:cat1] + dfcc[:cat2] + dfcc[:cat3] + dfcc[:cat4])
info("$(round(100*sum(dfcc, :cat5)/ncc, 1))% of trips tipped some other amount")

df5 = filter(x->x==1, dfcc, :cat5)
histogram(df5, :Tip_pct, bins=100, xlabel = "Tip %", ylabel = "Count",
    leg = nothing, title = "Histogram of tip % in Category 5 (N = $(size(df5, 1)))")
png(joinpath(plotdir, "q4-histogram-cat5"))
info("Q4: Histogram of tip percentages saved in q4-histogram-cat5.png")


#Define also a category for customers who picked the "other tip amount"
dfcc[:catcustom] = dfcc[:cat1] + dfcc[:cat5]
info("$(round(100*sum(dfcc, :catcustom)/ncc, 1))% of trips picked the 'other' amount")


#Now train binary classifiers

m0 = glm(catcustom ~ Fare_amount + Trip_distance + Tolls_amount + Periodic + Pickup_longitude + Pickup_latitude + Dropoff_longitude + Dropoff_latitude, dfcc, Binomial())

#If not custom, which choice did they pick?

dfnotcustom = dfcc#filter(x->x==0, dfcc, :catcustom)
m2 = glm(cat2 ~ Fare_amount + Trip_distance + Tolls_amount + Periodic + Pickup_longitude + Pickup_latitude + Dropoff_longitude + Dropoff_latitude, dfnotcustom, Binomial())

dfnot2 = dfcc#filter(x->x==0, dfnotcustom, :cat2)
m3 = glm(cat3 ~ Fare_amount + Trip_distance + Tolls_amount + Periodic + Pickup_longitude + Pickup_latitude + Dropoff_longitude + Dropoff_latitude, dfnotcustom, Binomial())

#If custom, did they choose 0%?

dfcustom = dfcc#filter(x->x==1, dfcc, :catcustom)
m1 = glm(cat1 ~ Fare_amount + Trip_distance + Tolls_amount + Periodic + Pickup_longitude + Pickup_latitude + Dropoff_longitude + Dropoff_latitude, dfcustom, Binomial())

#If other amount, try to predict tip percentage
df5 = dfcc#filter(x->x==0, dfcustom, :cat1)
m5 = lm(Tip_pct ~ Fare_amount + Trip_distance + Tolls_amount + Periodic + Pickup_longitude + Pickup_latitude + Dropoff_longitude + Dropoff_latitude, df5)

# Now evaluate the model constructed so far - does it correctly classify the five categories?

function mypredict(dfcc)
    #Classify based on the maximal score from each predictor
    p0 = Array(predict(m0, dfcc))
    p2 = Array(predict(m2, dfcc))
    p3 = Array(predict(m3, dfcc))
    p1 = Array(predict(m1, dfcc))

    pred = Array(Int, ncc)
    for i = 1:ncc
        scores = zeros(5)
        scores[1] = p0[i]*p1[i]                   #Other amount, chose 0
        scores[2] = (1-p0[i])*p2[i]               #not custom, 20%
        scores[3] = (1-p0[i])*(1-p2[i])*p3[i]     #not custom, not 20%, 25%
        scores[4] = (1-p0[i])*(1-p2[i])*(1-p3[i]) #not custom, not 20%, 30%
        scores[5] = p0[i]*(1-p1[i])               #Other amount, not 0
        pred[i] = predicted = indmax(scores)

        if i < 30
            println("Rec $i: $predicted $scores, $(sum(scores))")
        end
    end
    return pred
end
dfcc[:catpredicted] = pred = mypredict(dfcc)

#Build confusion matrix
Conf = zeros(Int, 5, 5)
for i in 1:ncc
    actual= if     get(dfcc[i, :cat1])==1   1
            elseif get(dfcc[i, :cat2])==1   2
            elseif get(dfcc[i, :cat3])==1   3
            elseif get(dfcc[i, :cat4])==1   4
            elseif get(dfcc[i, :cat5])==1   5
            else error()
        end
    Conf[actual, pred[i]] += 1
end
info("Confusion matrix")
display(Conf)

# Assemble the final classifier for credit card payments

function mymodel(df)
    n = size(df, 1)
    if :catpredicted ∉ names(df) #Run prediction if not present
        df[:catpredicted] = prediction = predict(dfcc)
    else
        prediction = Array(df[:catpredicted])
    end
    tips = Array(predict(m5, df)) #Fill in predictions from category 5
    for i in 1:n
        p = prediction[i]
        if     p==1 tips[i] = 0.0
        elseif p==2 tips[i] = 0.2 /1.2
        elseif p==3 tips[i] = 0.25/1.25
        elseif p==4 tips[i] = 0.3 /1.3
        end
    end
    return tips
end

info("Hybrid logistic-Least-squares regression model for credit payments:")
resid = mymodel(dfcc) - Array(dfcc[:Tip_pct])
histogram(resid, bins=120,
    title = "Residuals (rms = $(round(rms(resid),2)))",
    ylabel = "Count", xlabel = "Residual in tip %", label = "")
png(joinpath(plotdir, "q4-res-hybrid"))
info("Residuals from model saved to q4-res-hybrid.png")
