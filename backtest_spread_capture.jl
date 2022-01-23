using CSV
using DataFrames
using Dates
using Plots
plotly()

function calc_spread(mid_price, weighted_mid_price, bid_spread, ask_spread, mode) 
    if mode == :mid
        price = mid_price
    elseif mode == :weightedmid
        price = weighted_mid_price
    end
    return (100-bid_spread)/100*price , (100+ask_spread)/100*price 
end

function run_backtest(trades, bbo, mode=:mid; tick = 1, bid_spread=0.1, ask_spread = 0.1, stop_loss = 1.0, order_refresh_time = 60)
    
    btcTrades = DataFrame(CSV.File(trades))
    btcBBO = DataFrame(CSV.File(bbo))
    
    in_position = false; direction = :neutral
    next_order_time = nothing
    bid_price = NaN; ask_price = NaN; sl_price = NaN
    
    start_time = btcTrades[1, :time] > btcBBO[1, :time] ? btcTrades[1, :time] : btcBBO[1, :time]
    end_time = btcTrades[end, :time] > btcBBO[end, :time] ? btcBBO[end, :time] : btcTrades[end, :time]    
    open_price = NaN; close_tp_price = NaN; close_sl_price = NaN
    n_profit = 0; n_loss = 0
    
    df = DataFrame(time = DateTime[], mid_price = Float64[], weighted_mid_price = Float64[], 
    bid_price = Float64[], ask_price = Float64[], sl_price = Float64[], 
    open_price = Float64[], close_tp_price = Float64[], close_sl_price = Float64[])
    
    
    for current_time in range(start_time, end_time, step=Dates.Second(tick))
        trade_price = btcTrades[btcTrades[!,:time] .< current_time, :][end,:price]
        time_ind = btcBBO[!,:time] .<= current_time
        bid = btcBBO[time_ind, :][end,:bid_price]
        ask = btcBBO[time_ind, :][end,:ask_price]
        bidqty = btcBBO[time_ind, :][end,:bid_quantity]
        askqty = btcBBO[time_ind, :][end,:ask_quantity]
        
        mid_price = (bid+ask)/2.
        weighted_mid_price = (bid*bidqty + ask*askqty)/(bidqty+askqty)
        
        open_price = NaN; close_tp_price = NaN; close_sl_price = NaN
        
        if in_position == false
            #If no orders exist yet, make new orders
            if isnothing(next_order_time) || current_time > next_order_time
                bid_price, ask_price  = calc_spread(mid_price, weighted_mid_price, bid_spread, ask_spread, mode) 
                next_order_time = current_time + Dates.Second(order_refresh_time)
            end
            
            #Check if any position is opened
            if trade_price < bid_price 
                in_position = true
                direction = :long
                sl_price = (100-stop_loss)/100*bid_price
                open_price = bid_price 
                bid_price = NaN
            elseif trade_price > ask_price 
                in_position = true
                direction = :short
                sl_price = (100+stop_loss)/100*ask_price
                open_price = ask_price
                ask_price = NaN
            end
            
        else
            if direction == :long
                if trade_price > ask_price 
                    n_profit += 1
                    in_position = false
                    direction = :neutral
                    close_tp_price = ask_price
                    sl_price = NaN 
                    bid_price, ask_price  = calc_spread(mid_price, weighted_mid_price, bid_spread, ask_spread, mode)  
                    next_order_time = current_time + Dates.Second(order_refresh_time)
                    
                elseif trade_price < sl_price 
                    n_loss += 1
                    in_position = false
                    direction = :neutral
                    close_sl_price = sl_price
                    sl_price = NaN 
                    bid_price, ask_price  = calc_spread(mid_price, weighted_mid_price, bid_spread, ask_spread, mode) 
                    next_order_time = current_time + Dates.Second(order_refresh_time)
                end
            else
                if trade_price < bid_price 
                    n_profit += 1
                    in_position = false
                    direction = :neutral
                    sl_price = NaN
                    close_tp_price = bid_price 
                    bid_price, ask_price  = calc_spread(mid_price, weighted_mid_price, bid_spread, ask_spread, mode) 
                    next_order_time = current_time + Dates.Second(order_refresh_time)      
                elseif trade_price > sl_price 
                    n_loss += 1
                    in_position = false
                    direction = :neutral
                    close_sl_price = sl_price
                    sl_price = NaN
                    bid_price, ask_price  = calc_spread(mid_price, weighted_mid_price, bid_spread, ask_spread, mode) 
                    next_order_time = current_time + Dates.Second(order_refresh_time)
                end
            end
        end
        push!(df, [current_time mid_price weighted_mid_price bid_price ask_price sl_price open_price close_tp_price close_sl_price])
    end
    mode == :mid ? println("Using MID price") : println("using WEIGHTED MID price") 
    println("Start Time $(start_time),  End Time $(end_time)")
    println("Bid spread: $(bid_spread), Ask spread: $(ask_spread), Stop loss: $(stop_loss), Order refresh time: $(order_refresh_time)")
    println("Spreads captured $(n_profit) times")
    println("Failed to capture spread $(n_loss) times")
    
    return df, n_profit, n_loss
end

function plot_result(df)
    plot(df[!,:time], df[!,:mid_price], linestyle=:dot, color=:black, label="mid price", xaxis=false)
    plot!(df[!,:time], df[!,:weighted_mid_price], linestyle=:dashdot, color=:brown, label = "weighted mid price")
    plot!(df[!,:time], df[!,:bid_price], color=:blue, label="open bid_order")
    plot!(df[!,:time], df[!,:sl_price], linestyle=:dot, color=:magenta, label="open stop loss")
    plot!(df[!,:time], df[!,:ask_price], color=:red, label="open ask_order")
    plot!(df[!,:time], df[!,:open_price], markershape=:diamond, color=:black, label="position open")   
    plot!(df[!,:time], df[!,:close_tp_price], markershape=:circle, color=:blue, label="position closed (profit)")
    plot!(df[!,:time], df[!,:close_sl_price], markershape=:xcross, color=:red, label="position closed (loss)")
end
    
   

    
    
    