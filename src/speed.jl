#!/usr/bin/env julia

# Speed distribution

speed = Array(df[:Trip_distance])./float(Array(df[:Lpep_dropoff_datetime] - df[:lpep_pickup_datetime]))*3600000
speed[!isfinite(speed)] = 0 #Correct for possible division by 0
df[:Speed] = speed

n = size(df, 1)
dfspeed = filter(x-> 1<x<100, df, :Speed)
nbad = n - size(dfspeed, 1)
info("Q5: Removing $nbad nonsensical speeds")
n -= nbad
info("Analyzing $n records")

histogram(dfspeed, :Speed, bins=120, label = "histogram",
    leg = nothing, ylabel = "Count", xlabel = "Average speed (mph)")

#Fit to a model
d = fit(Gamma, dfspeed, :Speed)
xmin = 0
xmax = 100
nbins = 100

pdfplot!(d, scale=size(dfspeed, 1), xlims=(xmin, xmax), bins=nbins, color=:black, width=2,
title = "Fit to Gamma(k=$(round(d.α, 1)), theta=$(round(d.θ, 1))) (N = $n)")
png(joinpath(plotdir, "q5-speed"))
info("Histogram of speeds saved to q5-speed.png")

###############################################################################
#Are the average trip speeds are materially the same in all weeks of September?

#Add derived variable: week of the year
dfspeed[:Week] = map(Dates.week, dfspeed, :lpep_pickup_datetime)

dfweekly = by(dfspeed, :Week) do group
    df = DataFrame(
        μ = mean(group, :Speed),
        σ = mean(group, :Speed),
        N = size(group, 1),
    )
end
display(dfweekly)

#Do many paired Welch's t-tests
nw = size(dfweekly, 1)
ps = UpperTriangular(zeros(nw, nw))
for i = 1:nw
    σi = get(dfweekly[i, :σ])
    μi = get(dfweekly[i, :μ])
    Ni = get(dfweekly[i, :N])
    for j = i+1:nw
        σj = get(dfweekly[j, :σ])
        μj = get(dfweekly[j, :μ])
        Nj = get(dfweekly[j, :N])
        sp = √(((Ni-1)*σi^2 + (Nj-1)*σj^2)/(Ni + Nj - 2))

        t = (μi - μj)/(sp*sqrt(1/Ni + 1/Nj))

        #Compute effective degrees of freedom using the Welch–Satterthwaite equation
        dof = (σi^2/Ni + σj^2/Nj)^2/((σi^2/Ni)^2/(Ni-1) + (σj^2/Nj)^2/(Nj-1))

        #Apply Bonferroni's correction for multiple comparisons
        #Extra factor of 2 is for two-sided testing
        ps[i, j] = cdf(TDist(100), -abs(t))*(nw*(nw-1)/2)*2
    end
end
info("p-scores:")
display(ps)

###############################################################################
# Can you build up a hypothesis of average trip speed as a function of time of day?

dfspeed[:HourCont] = map(hourofday, dfspeed, :lpep_pickup_datetime)
dfspeed[:HourMin] = map(hourofday_bymin, dfspeed, :lpep_pickup_datetime)

speedsummary = by(dfspeed, :HourMin) do group
    μ = mean(group, :Speed)
    σ = std(group, :Speed)

    DataFrame(
        meanspeed = μ,
        p5speed = μ - 2σ,
        p95speed = μ + 2σ,
        medianspeed = median(group, :Speed),
        q5speed = quantile(group, :Speed, 0.1),
        q95speed = quantile(group, :Speed, 0.9),
        N = size(group, 1)
    )
end


scatter(dfspeed, :HourCont, :Speed, alpha=0.003, markerstrokewidth=0,
    label = "Raw", ylims = (0, 40), xlims = (0, 24),
    xlabel = "Hour of day", ylabel = "Speed (mph)")

plot!(speedsummary, :HourMin, :p5speed, c = :pink, label = "mean-2sig")
plot!(speedsummary, :HourMin, :p95speed, c = :pink, label = "mean+2sig")
plot!(speedsummary, :HourMin, :meanspeed, c = :red, label = "mean")

plot!(speedsummary, :HourMin, :q5speed, c = :lightblue, label = "q=0.05")
plot!(speedsummary, :HourMin, :q95speed, c = :lightblue, label = "q=0.95")
plot!(speedsummary, :HourMin, :medianspeed, c = :blue, label = "q=0.5")

png(joinpath(plotdir, "q5-speedbyhour"))
info("Summary of speeds by hour saved to q5-speedbyhour.png")

# All of the summary statistics look similar in shape, focus on mean

# Since time of day is periodic, it's natural to look at its Fourier modes
pow = fft(Array(speedsummary[:meanspeed]))
f = 60//size(pow, 1) #frequency of the fft in Hz
bar(1:20, abs(pow[1:20]), xlabel = "Fourier component ($f Hz)",
    ylabel = "Magnitude (mph)", leg = nothing)
png(joinpath(plotdir, "q5-speedbyhour-modes"))
info("Mode plot saved to q5-speedbyhour-modes.png")

#Filter out only largest modes (+ DC component)
nmodes = 7
pow[2+nmodes:end-nmodes] = 0
p = real(ifft(pow))


plot(speedsummary, :HourMin, :meanspeed, c = :red, label = "mean")
plot!(Array(speedsummary[:HourMin]), p, c = :black, linewidth = 3, label = "$nmodes modes", title = "Fit of Fourier modes to mean")
png(joinpath(plotdir, "q5-speedbyhour-modefit"))
info("Mode fitting plot saved to q5-speedbyhour-modefit.png")

#Look at residuals
resid = Array(speedsummary[:meanspeed]) - p
plot(Array(speedsummary[:HourMin]), resid, leg = nothing,
    xlabel = "Hour of day", ylabel = "Residual (mph)",
    title = "Residual of fit to Fourier modes")
png(joinpath(plotdir, "q5-speedbyhour-resid"))
info("Residual plot saved to q5-speedbyhour-resid.png")

#######################################

# Note that there is an interesting hysteresis in the data!

scatter(speedsummary, :N, :meanspeed, xlabel = "Number of trips per minute", ylabel = "Mean average speed (mph)", zlabel = "Hour", zcolor = speedsummary[:HourMin], label = "")

#Do a similar Fourier mode fit for the number of trips per minute
pow = fft(Array(speedsummary[:N]))
pow[2+nmodes:end-nmodes] = 0
pN = real(ifft(pow))

plot!(pN, p, c = :grey, linewidth = 2, label = "$nmodes modes")


png(joinpath(plotdir, "q5-speedbyhour-traffic"))
info("Speeds by hour vs trips saved to q5-speedbyhour-traffic.png")
