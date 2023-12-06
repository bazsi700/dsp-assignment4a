### A Pluto.jl notebook ###
# v0.19.30

using Markdown
using InteractiveUtils

# ╔═╡ ad405d72-2f5b-48c4-a729-5e3c2dc6b0fa
using DSP, Plots, FFTW, ImageIO, ImageShow, Statistics

# ╔═╡ 6b914e30-84a1-11ee-1fbf-e9e3c597b367
function load_iq(fn)
	len = div(filesize(fn), sizeof(ComplexF32))
	z = Vector{ComplexF32}(undef,len)
	read!(fn, z)
end

# ╔═╡ d47480aa-dac6-495c-914d-ac01e41adf00
function resample(x; old_fs, new_fs)
	old_len = length(x)
	
	time_period = (old_len/old_fs)
	new_len = ceil(Int,time_period * new_fs)
	
	new_x = Vector{ComplexF32}(undef,new_len)

	for i in 1:new_len
		time = i/new_fs

		### Using nearest neighbour
		
		# closest_old_sample = x[min(old_len,max(1,round(Int,time*old_fs)))]
		# new_x[i] = closest_old_sample

		
		### linear sampling
		
		# maxed at len -1 as we want the one above too
		old_sample_ind = min(old_len-1,max(1,time*old_fs)) 
		below = floor(Int,old_sample_ind)
		above = below + 1
		new_x[i] = x[below] * (above - old_sample_ind) + 
				   x[above] * (old_sample_ind - below)		

		
		### sinc reconstruction
		
		# local new_value = 0
		# old_sample_ind = round(Int,time*old_fs)
		# for ind in max(old_sample_ind-10,1):min(old_sample_ind+10,old_len)
		# 	ind_time = ind/old_fs
		# 	new_value += sinc((time - ind_time) * new_fs) * x[ind]
		# end
		# new_x[i] = new_value
		
	end
	
	return new_x
end

# ╔═╡ b2aadea1-c363-4a2b-ac41-e7968a21941c
function restore_aspect(matrix; aspect)
	restored = Matrix{typeof(matrix[1,1])}(undef,size(matrix)[1]*aspect,size(matrix)[2])

	for i in 1:size(matrix)[1]
		for k in 1:aspect
			restored[(i-1)*aspect+k,:] .= matrix[i,:]
		end
	end

	return restored
end

# ╔═╡ d46609b0-9f1f-42e2-8077-5dc70f63e750
function show_image(matrix; aspect)
	normalised = abs.(matrix) / maximum(abs.(matrix))
	
	return Gray.(restore_aspect(normalised; aspect))
end

# ╔═╡ 03351222-5867-4b68-bb91-0193ae553c8b
function show_rgb_image(red_matrix, green_matrix, blue_matrix; aspect)
	max = maximum(maximum.([red_matrix,green_matrix,blue_matrix]))
	normalised_red = red_matrix ./ max
	normalised_green = green_matrix ./ max
	normalised_blue = blue_matrix ./ max

	combined = RGB{Float32}.(normalised_red,normalised_green,normalised_blue)
	
	return restore_aspect(combined; aspect)

end

# ╔═╡ 3b638899-e765-4866-b015-f9ac17024490
function angle_to_hue(x)
	y = 0
	if x < 0
		y = (2pi+x)
	else
		y = x
	end
	return y * 180/pi
end

# ╔═╡ c8daa5f1-673c-4d18-b2fc-e99349b3d9f7
# Takes hue as an angle from -pi to pi
function show_hsv_image(hue_matrix, brigthness_matrix; aspect)
	max = maximum(brigthness_matrix)
	normalised_brightness = brigthness_matrix / max

	normalised_hue = angle_to_hue.(hue_matrix)

	combined = HSV{Float32}.(normalised_hue,1,normalised_brightness)
	
	return restore_aspect(combined; aspect)

end

# ╔═╡ ddce8d2a-9333-455b-bb38-8554f3c52953
function plot_spectrogram(iq; fs, title)
	# Code taken from slide 89
	s = fftshift(spectrogram(iq[1:1000000], 2048; fs, window=hamming))
	ps = 10*log10.(power(s)); mx = maximum(ps)
	heatmap(time(s), freq(s), ps; xlabel="time [s]", ylabel="frequency [Hz]", clim=(mx-70, mx), title)
end

# ╔═╡ c7703d65-54bd-42e9-828c-86daee45206b
function normalised_correlation(x,y)
	if length(x) != length(y)
		error("Need equal x and y length")
	end
	# using code from slide 153
 	o = [1:length(x); length(x)-1:-1:1]
	return xcorr(x,y) ./ o
end

# ╔═╡ 0ca1f84e-c10f-42f5-99bf-50ef382d9b23
function rms(x)
	return sqrt(mean(abs.(x.*x)))
end

# ╔═╡ 591b1016-25fa-4105-abd7-07b623f28a25
begin
	centre_freq = 425
	fn="scene3-640x480-60-" * string(centre_freq) * "M-64M-40M.dat"
	fs = 64e6
	fc = centre_freq * 1e6
	
	
	xt = 800
	yt = 525
end

# ╔═╡ 38da31b8-d574-46ad-a52e-346ff22c9b5b
begin
	# Manually adjusted from 25.175e6 to remove shearing in one frame
	fp_guess = 25.2e6
	
	fh_guess = fp_guess/xt
	fv_guess = fh_guess/yt
end

# ╔═╡ 108ae3b2-7300-4a70-a3e6-ee57819dd372
# ╠═╡ disabled = true
#=╠═╡
begin
	noise_fn="noise-640x480-60-" * string(centre_freq) * "M-64M-40M.dat"
	noise_iq = load_iq(noise_fn)
end
  ╠═╡ =#

# ╔═╡ 98e356ba-322f-4993-bab4-551e8bafcb02
begin
	iq = load_iq(fn)
	# iq = load_iq(fn) + 64 .* noise_iq
end

# ╔═╡ 95ecaf8b-ab63-4579-8535-88418b06c7d5
function get_image_matrix(iq; m, fh, fp)

	fr = m * fp
	resampled = resample(iq,old_fs = fs, new_fs = fr)
	
	len = length(resampled)

	matrix = zeros(typeof(iq[1]),ceil(Int,len/(xt*m)),xt*m)

	for i in 1:size(matrix)[1]
		indices = 1:size(matrix)[2]
		resampled_indices = min.(len,(i-1)*xt*m .+ indices)
		matrix[i,:] .= resampled[resampled_indices]
	end

	return matrix
end

# ╔═╡ f170cead-41ba-4690-acfe-6bf58f4ad5e7
m = 3

# ╔═╡ 98855c90-4e60-49a5-9685-f88036e45521
# ╠═╡ disabled = true
#=╠═╡
begin
	# Throw away first few samples to align the resulting image
	local cropped_iq = iq[523280:Int(25e6)] 
	
	matrix1 = get_image_matrix(cropped_iq; m, fh=fh_guess, fp = fp_guess)
end
  ╠═╡ =#

# ╔═╡ b5c25c12-5a33-4e9b-90fa-f994ece17602
#=╠═╡
show_image(vcat(matrix1[1:250,:], matrix1[yt*10+251:yt*10+500,:]); aspect=m)
  ╠═╡ =#

# ╔═╡ eff40b96-1784-4e98-b327-40ac77af15b2
length(iq)

# ╔═╡ 3c49a223-ed4e-45c6-a701-4bd5abaf15b5
begin
	# Taking abs before the cross correlation seems to make the peak sharper
	# but the non-correlated parts gain a correlation as well

	# We use coherent averaging for 225MHz
	# corr = abs.(xcorr(iq,iq))

	
	abs_iq = abs.(iq)
	corr = xcorr(abs_iq,abs_iq)

	
	leng = length(corr)
end

# ╔═╡ 6d0d50df-958a-4e11-86e7-20069058799b
begin
	# the midpoint is the crosscorrelation with offset 0
	midpoint = round(Int,(length(corr)+1)/2)
	
	# The offset 0 is the first frame
	frame_inds = zeros(1)	

	# For each offset we check in what neighbourhood it is maximal
	# if it's at least 6e5 it is the offset of a frame

	# For <=250Mhz centre frequency we can only use the first 10e6 samples
	# as the noise is too large for it to work outside that
	for i in 1:Int(25e6) # 45e5 for merged
		closest_bigger = 0
		for j in 1:midpoint
			if corr[midpoint+i-j] > corr[midpoint+i] || 
			   corr[midpoint+i+j] > corr[midpoint+i]
				closest_bigger = j
				break
			end
		end
		if closest_bigger > 6e5 # 18e5 for merged
			print(i, " ", closest_bigger,"\n")
			append!(frame_inds,i)
		end
	end
end

# ╔═╡ 6093f46a-39ff-40b6-979b-b370ae91f19b
begin
	cropped = corr[round(Int,midpoint-fs/20):4000:round(Int,midpoint+fs/20)]
	plot(abs.(cropped))
end

# ╔═╡ e0c0c03e-44d6-4fac-9c6a-493a24673c3b
argmax(cropped)

# ╔═╡ 80261586-4978-4701-95d4-89b2b465c22e
begin
	mean_diff = mean(frame_inds[2:end] .- frame_inds[1:end-1])
	print(mean_diff)
end

# ╔═╡ b35869a3-ab7b-4d85-b379-b3b68b200f60
begin	
	fv = fs/mean_diff

	# used when above fails
	# fv = 2.520009689e7 / xt / yt 
	
	fh = fv * yt
	fp = fh * xt
end

# ╔═╡ ef678d53-0bcc-4b22-8a95-2240259ecf7e
# begin
# 	row_len = length(iq) / fh
	
# 	row_xcorrs = abs.([ mean(abs.(
# 		iq[1123+round(Int,i*row_len+1):1123+round(Int,(i+1)*row_len)]
		
# 	)) for i=1:1000])

# 	start_row = argmin(row_xcorrs)
	
# 	to_crop = round(Int,start_row * row_len)
# 	print(start_row, " ", to_crop)
# 	plot(row_xcorrs[1:1000])
# end

# ╔═╡ 421a27ef-2cf7-4aca-a101-60862acfd2ad
# Figure out where we need to crop. 
# Take 2 frames which are the average of 15 frames each
begin
	matr_multi = abs.(get_image_matrix(iq; m=1, fh, fp))
	matr = mean([matr_multi[(i-1)*1*yt+1:(i+1)*1*yt,:] for i=1:15])
end

# ╔═╡ be010908-6411-4b08-a2d4-6bcc036e0322
begin
	# Take column standard deviations in a rolling window of 160
	# which is the length of the blanking period
	col_stds = std.([(circshift(matr,(0,-j))[:,1:160]) for j =0:(xt-1)])
	# 48 for 375MHz and 350MHz

	col_std_diffs = (col_stds .- circshift(col_stds,10)) .* 
					(col_stds .- circshift(col_stds,-10))

	# used for fc = 350,375
	# min_col = argmax(col_std_diffs) 
	# start_col = (min_col + 48)%xt
	
	min_col = argmin(col_stds) 	
	start_col = (min_col + 160)%xt

	print(min_col, " ", start_col)	
	plot(col_stds)
end

# ╔═╡ f1545d8c-ea95-4975-8d5f-81543545ff16
plot(col_stds, title= "Rolling window std. of columns")

# ╔═╡ f4709423-61a7-4cf0-b94d-0c79ccd53b64
plot(col_std_diffs)

# ╔═╡ 8ee2fd42-44a3-43e3-b757-abc0e0fc60ee
begin
	rot_matr = circshift(matr,(0,-start_col))
	# Take row standard deviations in a rolling window of 45
	# which is the vertical blanking period in VESA
	# Only take it for the actual picture, i.e. the first 525 cols
	row_stds = std.([abs.(rot_matr[i:i+44,1:525]) for i =1:yt])

	min_row = argmin(row_stds[1:yt])
	start_row = (min_row + 45)%yt

	print(min_row, " ", start_row)
	plot(abs.(row_stds))
end

# ╔═╡ c8b86a54-5c0f-4440-b488-1db8d8de7d3f
plot(row_stds, title= "Rolling window std. of rows")

# ╔═╡ 05b49778-b296-4c9f-9b63-d8b7d4914ca6
begin
	row_stds2 = std.([abs.(rot_matr[i:i+32,1:525]) for i =1:yt])
end

# ╔═╡ 79a32dd6-bf2b-4368-aa68-e6b20116b1cb
to_crop = round(Int, (start_row * xt + start_col) * fs / fp) + 1

# ╔═╡ 87969076-ae2e-4f3d-985c-fa01edaf90d1
begin
	# We take abs value before averaging so the phases dont cancel out
	grayscale_matr = abs.(get_image_matrix(iq[to_crop:end];m, fh, fp))
	show_image(grayscale_matr[1:yt,:]; aspect=m)
end

# ╔═╡ 416a6f2a-6eac-4d0d-b714-f13aa62584ae
begin
	show_image(vcat(grayscale_matr[1:250,:], grayscale_matr[yt*50+251:yt*50+500,:]); aspect=m)
end

# ╔═╡ e9b52bad-0d37-4a65-9396-551dc0437c25
begin
	grayscale_avg = mean([grayscale_matr[(i-1)*yt+1:i*yt,:] for i=1:55])
	show_image(grayscale_avg; aspect=m)
end

# ╔═╡ 57b5129c-c748-4cdc-b1d3-50720c0d8a44
plot_spectrogram(iq; fs, title = "spectrogram of raw IQ")

# ╔═╡ 0bec7954-a39b-4504-afe3-e493a3e1d267
fc

# ╔═╡ ab8e7da2-5963-4e8e-b0ca-33ce124d9ff7
fp

# ╔═╡ 32d96b01-337c-4d14-8060-457f97795ed9
# ╠═╡ disabled = true
#=╠═╡
begin
	complex_matrix = get_image_matrix(iq[to_crop:end]; m, fh, fp)
end
  ╠═╡ =#

# ╔═╡ ce8d18cc-0be5-4350-a9bb-c6e6d3d53938
#=╠═╡
begin
	hue_matrix = angle.(complex_matrix)
	brightness_matrix = abs.(complex_matrix).+0.0001
	show_hsv_image(hue_matrix[1:yt,:], brightness_matrix[1:yt,:]; aspect=m)
	# Pretty bad color bending
end
  ╠═╡ =#

# ╔═╡ a3f48f4e-cb82-42ba-b640-5859a7efefdf
#=╠═╡
begin
	# Periodic averaging without unrotation	
	avg_complex_matrix = mean([complex_matrix[(i-1)*yt+1:i*yt,:] for i=1:55])
	avg_hue_matrix = angle.(avg_complex_matrix)
	avg_brightness_matrix = abs.(avg_complex_matrix).+0.0001
	show_hsv_image(avg_hue_matrix[1:yt,:], avg_brightness_matrix[1:yt,:]; aspect=m)
	# Practically entire image disappears and just colour bands remain
end
  ╠═╡ =#

# ╔═╡ ee95baee-97a9-4c00-acc1-31e45255bb4c
#=╠═╡
begin
	show_rgb_image(real.(complex_matrix[1:yt,:]).+0.0001,
			       imag.(complex_matrix[1:yt,:]).+0.0001,
				   zeros(size(complex_matrix[1:yt,:]));
				   aspect=m)
end
  ╠═╡ =#

# ╔═╡ d9070b9e-4e60-4ad7-ae53-4c43a7c77557
begin
	# Take k to be such that fp*k-fc is closest to 0
	k = argmin( abs.(fp .* (1:30) .- fc) )
	print(k)
end

# ╔═╡ 76708ffa-8040-42e5-add0-67ae4b60a233
begin 
	fu = (fp*k-fc)
end

# ╔═╡ f98f648b-1f3b-4cf9-9445-e34263378c84
fu

# ╔═╡ 93e0cc64-9a71-455d-bbca-eea12e238dcd
cropped_iq = iq[to_crop:end]

# ╔═╡ 69ad9d11-9c92-4e96-a3d3-13a644b0ee0b
# ╠═╡ disabled = true
#=╠═╡
begin
	unrotated_iq = cropped_iq .* cispi.(2 * (-fu) .* (1:length(cropped_iq)) / fs)
end
  ╠═╡ =#

# ╔═╡ 19ad92cd-071a-49a9-a119-6577a157a475
plot_spectrogram(cropped_iq; fs, title = "spectrogram of cropped IQ")

# ╔═╡ 8e81e078-8117-43b2-b40d-94b91edbc393
#=╠═╡
plot_spectrogram(unrotated_iq; fs, title = "spectrogram of unrotated IQ")
  ╠═╡ =#

# ╔═╡ 7443c66b-b709-4c37-860f-06f5eccf31a9
#=╠═╡
begin
	unrotated_matrix = get_image_matrix(unrotated_iq; m, fh, fp)
end
  ╠═╡ =#

# ╔═╡ 119c1e0c-57d9-4aa6-a720-ed8d4d0ad314
#=╠═╡
 begin
	unrotated_hue_matrix = angle.(unrotated_matrix)
	unrotated_brightness_matrix = abs.(unrotated_matrix).+0.0001
	show_hsv_image(unrotated_hue_matrix[1:yt,:],
				   unrotated_brightness_matrix[1:yt,:]; aspect=m)
	# Looks better but still some colorbanding
end
  ╠═╡ =#

# ╔═╡ 840d2be9-8fde-449c-a121-35efc9a8de90
#=╠═╡
begin
	# Periodic averaging with unrotation	
	avg_unrotated_matrix = mean([unrotated_matrix[(i-1)*yt+1:i*yt,:] for i=1:5])
	avg_unrotated_hue_matrix = angle.(avg_unrotated_matrix)
	avg_unrotated_brightness_matrix = abs.(avg_unrotated_matrix).+0.0001
	show_hsv_image(avg_unrotated_hue_matrix[1:yt,:],
				   avg_unrotated_brightness_matrix[1:yt,:]; aspect=m)
	# We got rid of most of colour banding
end
  ╠═╡ =#

# ╔═╡ fa95d864-fe82-4996-9bbd-ad32a968212f
#=╠═╡
begin
	avg_unrotated_matrix2 = mean([unrotated_matrix[(i-1)*yt+1:i*yt,:] for i=30:35])
	avg_unrotated_hue_matrix2 = angle.(avg_unrotated_matrix2)
	avg_unrotated_brightness_matrix2 = abs.(avg_unrotated_matrix2).+0.0001
	show_hsv_image(vcat(avg_unrotated_hue_matrix[1:250,:],
						 avg_unrotated_hue_matrix2[251:yt,:]),
				   vcat(avg_unrotated_brightness_matrix[1:250,:],
						 avg_unrotated_brightness_matrix2[251:yt,:]);
				   aspect=m)
	# Among multiple frames there is still colour banding
end
  ╠═╡ =#

# ╔═╡ b77af2d9-68c0-447e-abf9-5bc8fccbbfe4
#=╠═╡
begin
	show_hsv_image(
		vcat([unrotated_hue_matrix[(i-1)*yt+10*(i-1)+1:(i-1)*yt+10*i,:] 
							for i = 1:50
						]...),
		vcat([unrotated_brightness_matrix[(i-1)*yt+10*(i-1)+1:(i-1)*yt+10*i,:] 
							for i = 1:50
				   		]...);
				   aspect=m)
	# Among multiple frames there is still some colour banding
end
  ╠═╡ =#

# ╔═╡ d904528a-559d-450c-a0f2-60926933d6db
#=╠═╡
begin
	# Periodic averaging with unrotation	
	full_avg_unrotated_matrix = mean([unrotated_matrix[(i-1)*yt+1:i*yt,:] for i=1:55])
	full_avg_unrotated_hue_matrix = angle.(full_avg_unrotated_matrix)
	full_avg_unrotated_brightness_matrix = abs.(full_avg_unrotated_matrix).+0.0001
	show_hsv_image(full_avg_unrotated_hue_matrix[1:yt,:],
				   full_avg_unrotated_brightness_matrix[1:yt,:]; aspect=m)
	# We got rid of most of colour banding
end
  ╠═╡ =#

# ╔═╡ 36f92b7f-66c1-4b6a-b4e3-8216a46ba022
# FM demodulation code from assignment 3
function fm_demodulate(z)
	# dzdt = (z[2:end] .- z[1:(end-1)]) .* fs

	# Using the first of "other practical approaches" from slide 177
	# s = imag.(dzdt .* conj.(z[2:end])) ./ (abs.(z[2:end]).^2)  ./ 2pi
	
	# s = imag(dzdt ./ (z[2:end])) ./ (2pi)

	# s = angle.((z[2:end]) ./ dzdt) 

	z_angle = Unwrap.unwrap(angle.(z))
	s = (((@view z_angle[2:end]) .- (@view z_angle[1:end-1]))) * fs/2pi

	
	return s
end

# ╔═╡ 260e99fe-11e2-4d80-8d3c-3affdce0265e
fp*k-fc

# ╔═╡ 691fd46d-bfad-44a1-8f54-b41c8e878662
begin
	# We take abs as the centre has to be positive
	bandpass_centre = abs(fp*k-fc)
	bandpass_width = 50
end

# ╔═╡ 539d901a-f350-4b74-a8a9-896a810f4105
# ╠═╡ disabled = true
#=╠═╡
begin
	bandpass_filter = digitalfilter(Bandpass(bandpass_centre-bandpass_width/2,
											 bandpass_centre+bandpass_width/2;
											 fs),
									Butterworth(10))
	bandpassed_iq = filtfilt(bandpass_filter,cropped_iq)
end
  ╠═╡ =#

# ╔═╡ 40ee0706-cd63-424c-ae26-8f7fe97d6748
begin
	local rotated = cropped_iq .* cispi.(2 * (-(fp*k-fc)) .* (1:length(cropped_iq)) / fs)
	local filter = digitalfilter(Lowpass(bandpass_width/2;fs),Butterworth(6))
	local filtered = filtfilt(filter,rotated) 
	lowpassed_iq = filtered .* cispi.((2 * ((fp*k-fc)/ fs)).*(1:length(cropped_iq)))
end

# ╔═╡ 6b8ac421-c52f-4048-90c4-7e2360263670
plot_spectrogram(lowpassed_iq; fs, title = "spectrogram of lowpassed IQ")

# ╔═╡ b7b759ef-6237-43b5-9ff2-f051c392fdd3
begin
	local angles = Unwrap.unwrap(angle.(lowpassed_iq))
	local diffs = angles[2:end] - angles[1:end-1]
	local dzdt = (lowpassed_iq[2:end] - lowpassed_iq[1:end-1]) ./ lowpassed_iq[2:end]
	plot(abs.(lowpassed_iq[Int(26.8e6):300:Int(26.9e6)]))
	plot(abs.(lowpassed_iq[1:30000:end]))
	plot(diffs[1:30000:end])
end

# ╔═╡ ce6ea415-d522-495f-8395-3c017befaa9f
demodulated = fm_demodulate(lowpassed_iq)

# ╔═╡ df61265a-d69e-4b0e-a0bc-d24e3dadbb85
plot(demodulated[1:30000:end])

# ╔═╡ 3e862e9d-2e06-493f-92fd-1e74371a77eb
plot(abs.(lowpassed_iq[1:30000:end]))

# ╔═╡ 4af6a1e2-1222-497b-8d2c-925c9b768991
#=╠═╡
plot(abs.(bandpassed_iq[1:30000:end]))
  ╠═╡ =#

# ╔═╡ 7aa0eb45-d2bb-4bbd-91b7-59702a76cf0e
mean(demodulated)

# ╔═╡ 9269927a-99c2-42e5-a7a4-24e3f27a01e5
begin
	demodulated_avg_frames = 
		[mean(@view demodulated[round(Int,(i-1)*fs/fv)+1:round(Int,i*fs/fv)+1]) 
						  	  for i=1:59]
end

# ╔═╡ e489a5b7-ad68-4299-b9a7-799df7722aff
begin
	demodulated_avgs = 
		vcat([zeros(round(Int,i*fs/fv)-round(Int,(i-1)*fs/fv)) .+ 
					demodulated_avg_frames[i]
						  	  for i=1:59]...)
	demodulated_avgs_padded = [demodulated_avgs ;
							   zeros(length(cropped_iq) - length(demodulated_avgs))]
end

# ╔═╡ 823f0e7d-f14d-40e5-a2a0-e03619d61f62
mean(demodulated_avgs)

# ╔═╡ ec01326e-cdc7-49e3-8b11-30b71c755421
fs/fv

# ╔═╡ 1fdc0843-b808-4d3c-8696-accf3345fc82
fs/fp * yt

# ╔═╡ a7b90a6a-6296-4d76-bae7-28d63f9321f9
plot(demodulated_avgs[1:5000:end])

# ╔═╡ 453bda0f-9dbd-477e-a5b4-a6d94d95cdf0
mean(demodulated_avgs)

# ╔═╡ 12a2792e-6cd0-4aca-bd49-9f74242d0286
mean(demodulated)

# ╔═╡ 6d3c060e-508f-45b4-a224-d641c88b3198
fu

# ╔═╡ 2afa3290-d955-4cbc-a8fc-c2591be9fbe4
fs

# ╔═╡ a4b34899-5439-4393-b3e5-beb4b9b89751
begin
	# We avg within the frames so that the noise doesn't disrupt it
	integral = cumsum(demodulated_avgs_padded)
	properly_unrotated_iq = cropped_iq .* cispi.(2 * -(integral ./ fs))

	
	# properly_unrotated_iq = 
	# 	cropped_iq .* cispi.(2 * (-mean(demodulated)) .* (1:length(cropped_iq)) / fs)
	# Using a constant unrotation seems better??

end

# ╔═╡ 5d7b325b-b051-47f8-ba8d-408bfd4cbac1
plot_spectrogram(properly_unrotated_iq;
				 fs, title = "spectrogram of properlyunrotated IQ")

# ╔═╡ eb367bc6-d678-482a-857a-456b462a895b
begin
	properly_unrotated_matrix = get_image_matrix(properly_unrotated_iq; m, fh, fp)[2*yt+1:end,:]
end

# ╔═╡ f79b2f14-32a5-4653-adfa-dbde382a00c8
 begin
	properly_unrotated_hue_matrix = angle.(properly_unrotated_matrix)
	properly_unrotated_brightness_matrix = abs.(properly_unrotated_matrix).+0.0001
	show_hsv_image(properly_unrotated_hue_matrix[1:yt,:],
				   properly_unrotated_brightness_matrix[1:yt,:]; aspect=m)
	# Got rid of colorbanding
end

# ╔═╡ 49f35353-877c-4510-8746-c87ecd7dc074
begin
	show_hsv_image(
		vcat([properly_unrotated_hue_matrix[(i-1)*yt+10*(i-1)+1:(i-1)*yt+10*i,:] 
							for i = 1:50
						]...),
		vcat([properly_unrotated_brightness_matrix[(i-1)*yt+10*(i-1)+1:(i-1)*yt+10*i,:] .+ 0.0001 
							for i = 1:50
				   		]...);
				   aspect=m)
	# There is no colour banding even across multiple frames
end

# ╔═╡ 84393a04-bb71-46f5-a8fc-ffcb69ce56e9
begin
	avg_properly_unrotated_matrix = 
		mean([properly_unrotated_matrix[(i-1)*yt+1:i*yt,:] for i=1:5])
	
	avg_properly_unrotated_hue_matrix = 
		angle.(avg_properly_unrotated_matrix)
	avg_properly_unrotated_brightness_matrix = 
		abs.(avg_properly_unrotated_matrix).+0.0001
end

# ╔═╡ 841a870a-4a15-4d7f-8b63-5a0139600f37
begin
	avg_properly_unrotated_matrix2 = 
		mean([properly_unrotated_matrix[(i-1)*yt+1:i*yt,:] for i=40:45])
	
	avg_properly_unrotated_hue_matrix2 = 
		angle.(avg_properly_unrotated_matrix2)
	avg_properly_unrotated_brightness_matrix2 = 
		abs.(avg_properly_unrotated_matrix2).+0.0001
	show_hsv_image(vcat(avg_properly_unrotated_hue_matrix[1:250,:],
						 avg_properly_unrotated_hue_matrix2[251:yt,:]),
				   vcat(avg_properly_unrotated_brightness_matrix[1:250,:],
						 avg_properly_unrotated_brightness_matrix2[251:yt,:]);
				   aspect=m)
	# Among multiple frames there is virtually no colour banding
end

# ╔═╡ f07fe636-87a4-4e91-8073-af5a7fa6803e
begin
	# Periodic averaging with unrotation	
	# Drop first few frames as demodulation weird there
	best_matrix = mean([properly_unrotated_matrix[(i-1)*yt+1:i*yt,:] for i=1:57])
end

# ╔═╡ 1850d59e-3985-46ed-8dcf-67226ae39324
begin
	best_hue_matrix = angle.(best_matrix)
	best_brightness_matrix = abs.(best_matrix).+0.0001
	show_hsv_image(best_hue_matrix,
				   best_brightness_matrix; aspect=m)
	# We got rid of most of colour banding
end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
DSP = "717857b8-e6f2-59f4-9121-6e50c889abd2"
FFTW = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
ImageIO = "82e4d734-157c-48bb-816b-45c225c6df19"
ImageShow = "4e3cecfd-b093-5904-9786-8bbb286a6a31"
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[compat]
DSP = "~0.7.9"
FFTW = "~1.7.1"
ImageIO = "~0.6.7"
ImageShow = "~0.3.8"
Plots = "~1.39.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.9.3"
manifest_format = "2.0"
project_hash = "cee9efc3b225e8c0ef24286d5a13163db4cbbf9c"

[[deps.AbstractFFTs]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "d92ad398961a3ed262d8bf04a1a2b8340f915fef"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.5.0"

    [deps.AbstractFFTs.extensions]
    AbstractFFTsChainRulesCoreExt = "ChainRulesCore"
    AbstractFFTsTestExt = "Test"

    [deps.AbstractFFTs.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.Adapt]]
deps = ["LinearAlgebra", "Requires"]
git-tree-sha1 = "02f731463748db57cc2ebfbd9fbc9ce8280d3433"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.7.1"

    [deps.Adapt.extensions]
    AdaptStaticArraysExt = "StaticArrays"

    [deps.Adapt.weakdeps]
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.AxisArrays]]
deps = ["Dates", "IntervalSets", "IterTools", "RangeArrays"]
git-tree-sha1 = "16351be62963a67ac4083f748fdb3cca58bfd52f"
uuid = "39de3d68-74b9-583c-8d2d-e117c070f3a9"
version = "0.4.7"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BitFlags]]
git-tree-sha1 = "43b1a4a8f797c1cddadf60499a8a077d4af2cd2d"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.7"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[deps.CEnum]]
git-tree-sha1 = "eb4cb44a499229b3b8426dcfb5dd85333951ff90"
uuid = "fa961155-64e5-5f13-b03f-caf6b980ea82"
version = "0.4.2"

[[deps.Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "CompilerSupportLibraries_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "4b859a208b2397a7a623a03449e4636bdb17bcf2"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.16.1+1"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "cd67fc487743b2f0fd4380d4cbd3a24660d0eec8"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.3"

[[deps.ColorSchemes]]
deps = ["ColorTypes", "ColorVectorSpace", "Colors", "FixedPointNumbers", "PrecompileTools", "Random"]
git-tree-sha1 = "67c1f244b991cad9b0aa4b7540fb758c2488b129"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.24.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[deps.ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "Requires", "Statistics", "TensorCore"]
git-tree-sha1 = "a1f44953f2382ebb937d60dafbe2deea4bd23249"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.10.0"
weakdeps = ["SpecialFunctions"]

    [deps.ColorVectorSpace.extensions]
    SpecialFunctionsExt = "SpecialFunctions"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "fc08e5930ee9a4e03f84bfb5211cb54e7769758a"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.10"

[[deps.Compat]]
deps = ["UUIDs"]
git-tree-sha1 = "8a62af3e248a8c4bad6b32cbbe663ae02275e32c"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.10.0"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.0.5+0"

[[deps.ConcurrentUtilities]]
deps = ["Serialization", "Sockets"]
git-tree-sha1 = "8cfa272e8bdedfa88b6aefbbca7c19f1befac519"
uuid = "f0e56b4a-5159-44fe-b623-3e5288b988bb"
version = "2.3.0"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "c53fc348ca4d40d7b371e71fd52251839080cbc9"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.5.4"

    [deps.ConstructionBase.extensions]
    ConstructionBaseIntervalSetsExt = "IntervalSets"
    ConstructionBaseStaticArraysExt = "StaticArrays"

    [deps.ConstructionBase.weakdeps]
    IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.Contour]]
git-tree-sha1 = "d05d9e7b7aedff4e5b51a029dced05cfb6125781"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.6.2"

[[deps.DSP]]
deps = ["Compat", "FFTW", "IterTools", "LinearAlgebra", "Polynomials", "Random", "Reexport", "SpecialFunctions", "Statistics"]
git-tree-sha1 = "f7f4319567fe769debfcf7f8c03d8da1dd4e2fb0"
uuid = "717857b8-e6f2-59f4-9121-6e50c889abd2"
version = "0.7.9"

[[deps.DataAPI]]
git-tree-sha1 = "8da84edb865b0b5b0100c0666a9bc9a0b71c553c"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.15.0"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "3dbd312d370723b6bb43ba9d02fc36abade4518d"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.15"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
git-tree-sha1 = "9e2f36d3c96a820c678f2f1f1782582fcf685bae"
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"
version = "1.9.1"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "2fb1e02f2b635d0845df5d7c167fec4dd739b00d"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.3"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.EpollShim_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "8e9441ee83492030ace98f9789a654a6d0b1f643"
uuid = "2702e6a9-849d-5ed8-8c21-79e8b8f9ee43"
version = "0.0.20230411+0"

[[deps.ExceptionUnwrapping]]
deps = ["Test"]
git-tree-sha1 = "e90caa41f5a86296e014e148ee061bd6c3edec96"
uuid = "460bff9d-24e4-43bc-9d9f-a8973cb893f4"
version = "0.1.9"

[[deps.Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "4558ab818dcceaab612d1bb8c19cee87eda2b83c"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.5.0+0"

[[deps.FFMPEG]]
deps = ["FFMPEG_jll"]
git-tree-sha1 = "b57e3acbe22f8484b4b5ff66a7499717fe1a9cc8"
uuid = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
version = "0.4.1"

[[deps.FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "PCRE2_jll", "Zlib_jll", "libaom_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "466d45dc38e15794ec7d5d63ec03d776a9aff36e"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.4+1"

[[deps.FFTW]]
deps = ["AbstractFFTs", "FFTW_jll", "LinearAlgebra", "MKL_jll", "Preferences", "Reexport"]
git-tree-sha1 = "b4fbdd20c889804969571cc589900803edda16b7"
uuid = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
version = "1.7.1"

[[deps.FFTW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c6033cc3892d0ef5bb9cd29b7f2f0331ea5184ea"
uuid = "f5851436-0d7a-5f13-b9de-f02708fd171a"
version = "3.3.10+0"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "299dc33549f68299137e51e6d49a13b5b1da9673"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.16.1"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[deps.Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[deps.FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "d8db6a5a2fe1381c1ea4ef2cab7c69c2de7f9ea0"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.13.1+0"

[[deps.FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.GLFW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libglvnd_jll", "Pkg", "Xorg_libXcursor_jll", "Xorg_libXi_jll", "Xorg_libXinerama_jll", "Xorg_libXrandr_jll"]
git-tree-sha1 = "d972031d28c8c8d9d7b41a536ad7bb0c2579caca"
uuid = "0656b61e-2033-5cc2-a64a-77c0f6c09b89"
version = "3.3.8+0"

[[deps.GR]]
deps = ["Artifacts", "Base64", "DelimitedFiles", "Downloads", "GR_jll", "HTTP", "JSON", "Libdl", "LinearAlgebra", "Pkg", "Preferences", "Printf", "Random", "Serialization", "Sockets", "TOML", "Tar", "Test", "UUIDs", "p7zip_jll"]
git-tree-sha1 = "27442171f28c952804dede8ff72828a96f2bfc1f"
uuid = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
version = "0.72.10"

[[deps.GR_jll]]
deps = ["Artifacts", "Bzip2_jll", "Cairo_jll", "FFMPEG_jll", "Fontconfig_jll", "FreeType2_jll", "GLFW_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pixman_jll", "Qt6Base_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "025d171a2847f616becc0f84c8dc62fe18f0f6dd"
uuid = "d2c73de3-f751-5644-a686-071e5b155ba9"
version = "0.72.10+0"

[[deps.Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[deps.Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE2_jll", "Zlib_jll"]
git-tree-sha1 = "e94c92c7bf4819685eb80186d51c43e71d4afa17"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.76.5+0"

[[deps.Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[deps.Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "ConcurrentUtilities", "Dates", "ExceptionUnwrapping", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "5eab648309e2e060198b45820af1a37182de3cce"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.10.0"

[[deps.HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "129acf094d168394e80ee1dc4bc06ec835e510a3"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+1"

[[deps.ImageAxes]]
deps = ["AxisArrays", "ImageBase", "ImageCore", "Reexport", "SimpleTraits"]
git-tree-sha1 = "2e4520d67b0cef90865b3ef727594d2a58e0e1f8"
uuid = "2803e5a7-5153-5ecf-9a86-9b4c37f5f5ac"
version = "0.6.11"

[[deps.ImageBase]]
deps = ["ImageCore", "Reexport"]
git-tree-sha1 = "eb49b82c172811fd2c86759fa0553a2221feb909"
uuid = "c817782e-172a-44cc-b673-b171935fbb9e"
version = "0.1.7"

[[deps.ImageCore]]
deps = ["AbstractFFTs", "ColorVectorSpace", "Colors", "FixedPointNumbers", "MappedArrays", "MosaicViews", "OffsetArrays", "PaddedViews", "PrecompileTools", "Reexport"]
git-tree-sha1 = "fc5d1d3443a124fde6e92d0260cd9e064eba69f8"
uuid = "a09fc81d-aa75-5fe9-8630-4744c3626534"
version = "0.10.1"

[[deps.ImageIO]]
deps = ["FileIO", "IndirectArrays", "JpegTurbo", "LazyModules", "Netpbm", "OpenEXR", "PNGFiles", "QOI", "Sixel", "TiffImages", "UUIDs"]
git-tree-sha1 = "bca20b2f5d00c4fbc192c3212da8fa79f4688009"
uuid = "82e4d734-157c-48bb-816b-45c225c6df19"
version = "0.6.7"

[[deps.ImageMetadata]]
deps = ["AxisArrays", "ImageAxes", "ImageBase", "ImageCore"]
git-tree-sha1 = "355e2b974f2e3212a75dfb60519de21361ad3cb7"
uuid = "bc367c6b-8a6b-528e-b4bd-a4b897500b49"
version = "0.9.9"

[[deps.ImageShow]]
deps = ["Base64", "ColorSchemes", "FileIO", "ImageBase", "ImageCore", "OffsetArrays", "StackViews"]
git-tree-sha1 = "3b5344bcdbdc11ad58f3b1956709b5b9345355de"
uuid = "4e3cecfd-b093-5904-9786-8bbb286a6a31"
version = "0.3.8"

[[deps.Imath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "3d09a9f60edf77f8a4d99f9e015e8fbf9989605d"
uuid = "905a6f67-0a94-5f89-b386-d35d92009cd1"
version = "3.1.7+0"

[[deps.IndirectArrays]]
git-tree-sha1 = "012e604e1c7458645cb8b436f8fba789a51b257f"
uuid = "9b13fd28-a010-5f03-acff-a1bbcff69959"
version = "1.0.0"

[[deps.Inflate]]
git-tree-sha1 = "ea8031dea4aff6bd41f1df8f2fdfb25b33626381"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.4"

[[deps.IntelOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ad37c091f7d7daf900963171600d7c1c5c3ede32"
uuid = "1d5cc7b8-4909-519e-a0f8-d0f5ad9712d0"
version = "2023.2.0+0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.IntervalSets]]
deps = ["Dates", "Random"]
git-tree-sha1 = "3d8866c029dd6b16e69e0d4a939c4dfcb98fac47"
uuid = "8197267c-284f-5f27-9208-e0e47529a953"
version = "0.7.8"
weakdeps = ["Statistics"]

    [deps.IntervalSets.extensions]
    IntervalSetsStatisticsExt = "Statistics"

[[deps.IrrationalConstants]]
git-tree-sha1 = "630b497eafcc20001bba38a4651b327dcfc491d2"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.2"

[[deps.IterTools]]
git-tree-sha1 = "4ced6667f9974fc5c5943fa5e2ef1ca43ea9e450"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.8.0"

[[deps.JLFzf]]
deps = ["Pipe", "REPL", "Random", "fzf_jll"]
git-tree-sha1 = "9fb0b890adab1c0a4a475d4210d51f228bfc250d"
uuid = "1019f520-868f-41f5-a6de-eb00f4b6a39c"
version = "0.1.6"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7e5d6779a1e09a36db2a7b6cff50942a0a7d0fca"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.5.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JpegTurbo]]
deps = ["CEnum", "FileIO", "ImageCore", "JpegTurbo_jll", "TOML"]
git-tree-sha1 = "d65930fa2bc96b07d7691c652d701dcbe7d9cf0b"
uuid = "b835a17e-a41a-41e7-81f0-2f016b05efe0"
version = "0.1.4"

[[deps.JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6f2675ef130a300a112286de91973805fcc5ffbc"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "2.1.91+0"

[[deps.LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[deps.LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bf36f528eec6634efc60d7ec062008f171071434"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "3.0.0+1"

[[deps.LLVMOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f689897ccbe049adb19a065c495e75f372ecd42b"
uuid = "1d63c593-3942-5779-bab2-d838dc0a180e"
version = "15.0.4+0"

[[deps.LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "50901ebc375ed41dbf8058da26f9de442febbbec"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.1"

[[deps.Latexify]]
deps = ["Formatting", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "OrderedCollections", "Printf", "Requires"]
git-tree-sha1 = "f428ae552340899a935973270b8d98e5a31c49fe"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.16.1"

    [deps.Latexify.extensions]
    DataFramesExt = "DataFrames"
    SymEngineExt = "SymEngine"

    [deps.Latexify.weakdeps]
    DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
    SymEngine = "123dc426-2d89-5057-bbad-38513e3affd8"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[deps.LazyModules]]
git-tree-sha1 = "a560dd966b386ac9ae60bdd3a3d3a326062d3c3e"
uuid = "8cdb02fc-e678-4876-92c5-9defec4f444e"
version = "0.3.1"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.3"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "7.84.0+0"

[[deps.LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.10.2+0"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "0b4a5d71f3e5200a7dff793393e09dfc2d874290"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+1"

[[deps.Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll", "Pkg"]
git-tree-sha1 = "64613c82a59c120435c067c2b809fc61cf5166ae"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.7+0"

[[deps.Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "6f73d1dd803986947b2c750138528a999a6c7733"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.6.0+0"

[[deps.Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "f9557a255370125b405568f9767d6d195822a175"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.17.0+0"

[[deps.Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c30530bf0effd46e15e0fdcf2b8636e78cbbd73"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.35.0+0"

[[deps.Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "XZ_jll", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "2da088d113af58221c52828a80378e16be7d037a"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.5.1+1"

[[deps.Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7f3efec06033682db852f8b3bc3c1d2b0a0ab066"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.36.0+0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "7d6dd4e9212aebaeed356de34ccf262a3cd415aa"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.26"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "c1dd6d7978c12545b4179fb6153b9250c96b0075"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "1.0.3"

[[deps.MKL_jll]]
deps = ["Artifacts", "IntelOpenMP_jll", "JLLWrappers", "LazyArtifacts", "Libdl", "Pkg"]
git-tree-sha1 = "eb006abbd7041c28e0d16260e50a24f8f9104913"
uuid = "856f044c-d86e-5d09-b602-aeab76dc8ba7"
version = "2023.2.0+0"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "9ee1618cbf5240e6d4e0371d6f24065083f60c48"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.11"

[[deps.MappedArrays]]
git-tree-sha1 = "2dab0221fe2b0f2cb6754eaa743cc266339f527e"
uuid = "dbb5928d-eab1-5f90-85c2-b9b0edb7c900"
version = "0.4.2"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "03a9b9718f5682ecb107ac9f7308991db4ce395b"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.7"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.2+0"

[[deps.Measures]]
git-tree-sha1 = "c13304c81eec1ed3af7fc20e75fb6b26092a1102"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.2"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "f66bdc5de519e8f8ae43bdc598782d35a25b1272"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.1.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MosaicViews]]
deps = ["MappedArrays", "OffsetArrays", "PaddedViews", "StackViews"]
git-tree-sha1 = "7b86a5d4d70a9f5cdf2dacb3cbe6d251d1a61dbe"
uuid = "e94cdb99-869f-56ef-bcf0-1ae2bcbe0389"
version = "0.3.4"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.10.11"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "0877504529a3e5c3343c6f8b4c0381e57e4387e4"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.2"

[[deps.Netpbm]]
deps = ["FileIO", "ImageCore", "ImageMetadata"]
git-tree-sha1 = "d92b107dbb887293622df7697a2223f9f8176fcd"
uuid = "f09324ee-3d7c-5217-9330-fc30815ba969"
version = "1.1.1"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.OffsetArrays]]
deps = ["Adapt"]
git-tree-sha1 = "2ac17d29c523ce1cd38e27785a7d23024853a4bb"
uuid = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
version = "1.12.10"

[[deps.Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "887579a3eb005446d514ab7aeac5d1d027658b8f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+1"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.21+4"

[[deps.OpenEXR]]
deps = ["Colors", "FileIO", "OpenEXR_jll"]
git-tree-sha1 = "327f53360fdb54df7ecd01e96ef1983536d1e633"
uuid = "52e1d378-f018-4a11-a4be-720524705ac7"
version = "0.3.2"

[[deps.OpenEXR_jll]]
deps = ["Artifacts", "Imath_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "a4ca623df1ae99d09bc9868b008262d0c0ac1e4f"
uuid = "18a262bb-aa17-5467-a713-aee519bc75cb"
version = "3.1.4+0"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.1+0"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "51901a49222b09e3743c65b8847687ae5fc78eb2"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.4.1"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "cc6e1927ac521b659af340e0ca45828a3ffc748f"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.0.12+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "2e73fe17cac3c62ad1aebe70d44c963c3cfdc3e3"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.6.2"

[[deps.PCRE2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "efcefdf7-47ab-520b-bdef-62a2eaa19f15"
version = "10.42.0+0"

[[deps.PNGFiles]]
deps = ["Base64", "CEnum", "ImageCore", "IndirectArrays", "OffsetArrays", "libpng_jll"]
git-tree-sha1 = "5ded86ccaf0647349231ed6c0822c10886d4a1ee"
uuid = "f57f5aa1-a3ce-4bc8-8ab9-96f992907883"
version = "0.4.1"

[[deps.PaddedViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "0fac6313486baae819364c52b4f483450a9d793f"
uuid = "5432bcbf-9aad-5242-b902-cca2824c8663"
version = "0.5.12"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "716e24b21538abc91f6205fd1d8363f39b442851"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.7.2"

[[deps.Pipe]]
git-tree-sha1 = "6842804e7867b115ca9de748a0cf6b364523c16d"
uuid = "b98c9c47-44ae-5843-9183-064241ee97a0"
version = "1.3.0"

[[deps.Pixman_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "LLVMOpenMP_jll", "Libdl"]
git-tree-sha1 = "64779bc4c9784fee475689a1752ef4d5747c5e87"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.42.2+0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.9.2"

[[deps.PkgVersion]]
deps = ["Pkg"]
git-tree-sha1 = "f9501cc0430a26bc3d156ae1b5b0c1b47af4d6da"
uuid = "eebad327-c553-4316-9ea0-9fa01ccd7688"
version = "0.3.3"

[[deps.PlotThemes]]
deps = ["PlotUtils", "Statistics"]
git-tree-sha1 = "1f03a2d339f42dca4a4da149c7e15e9b896ad899"
uuid = "ccf2f8ad-2431-5c83-bf29-c5338b663b6a"
version = "3.1.0"

[[deps.PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "PrecompileTools", "Printf", "Random", "Reexport", "Statistics"]
git-tree-sha1 = "f92e1315dadf8c46561fb9396e525f7200cdc227"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.3.5"

[[deps.Plots]]
deps = ["Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "JLFzf", "JSON", "LaTeXStrings", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "Pkg", "PlotThemes", "PlotUtils", "PrecompileTools", "Preferences", "Printf", "REPL", "Random", "RecipesBase", "RecipesPipeline", "Reexport", "RelocatableFolders", "Requires", "Scratch", "Showoff", "SparseArrays", "Statistics", "StatsBase", "UUIDs", "UnicodeFun", "UnitfulLatexify", "Unzip"]
git-tree-sha1 = "ccee59c6e48e6f2edf8a5b64dc817b6729f99eb5"
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.39.0"

    [deps.Plots.extensions]
    FileIOExt = "FileIO"
    GeometryBasicsExt = "GeometryBasics"
    IJuliaExt = "IJulia"
    ImageInTerminalExt = "ImageInTerminal"
    UnitfulExt = "Unitful"

    [deps.Plots.weakdeps]
    FileIO = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
    GeometryBasics = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
    IJulia = "7073ff75-c697-5162-941a-fcdaad2a7d2a"
    ImageInTerminal = "d8c32880-2388-543b-8c61-d9f865259254"
    Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[[deps.Polynomials]]
deps = ["LinearAlgebra", "RecipesBase", "Setfield", "SparseArrays"]
git-tree-sha1 = "ea78a2764f31715093de7ab495e12c0187f231d1"
uuid = "f27b6e38-b328-58d1-80ce-0feddd5e7a45"
version = "4.0.4"

    [deps.Polynomials.extensions]
    PolynomialsChainRulesCoreExt = "ChainRulesCore"
    PolynomialsFFTWExt = "FFTW"
    PolynomialsMakieCoreExt = "MakieCore"
    PolynomialsMutableArithmeticsExt = "MutableArithmetics"

    [deps.Polynomials.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    FFTW = "7a1cc6ca-52ef-59f5-83cd-3a7055c09341"
    MakieCore = "20f20a25-4f0e-4fdf-b5d1-57303727442b"
    MutableArithmetics = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "03b4c25b43cb84cee5c90aa9b5ea0a78fd848d2f"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.2.0"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "00805cd429dcb4870060ff49ef443486c262e38e"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.4.1"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.ProgressMeter]]
deps = ["Distributed", "Printf"]
git-tree-sha1 = "00099623ffee15972c16111bcf84c58a0051257c"
uuid = "92933f4c-e287-5a05-a399-4b506db050ca"
version = "1.9.0"

[[deps.QOI]]
deps = ["ColorTypes", "FileIO", "FixedPointNumbers"]
git-tree-sha1 = "18e8f4d1426e965c7b532ddd260599e1510d26ce"
uuid = "4b34888f-f399-49d4-9bb3-47ed5cae4e65"
version = "1.0.0"

[[deps.Qt6Base_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Fontconfig_jll", "Glib_jll", "JLLWrappers", "Libdl", "Libglvnd_jll", "OpenSSL_jll", "Vulkan_Loader_jll", "Xorg_libSM_jll", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Xorg_libxcb_jll", "Xorg_xcb_util_cursor_jll", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_keysyms_jll", "Xorg_xcb_util_renderutil_jll", "Xorg_xcb_util_wm_jll", "Zlib_jll", "libinput_jll", "xkbcommon_jll"]
git-tree-sha1 = "1dab79940e0a8098f59a5fa961234a58f43444e8"
uuid = "c0090381-4147-56d7-9ebc-da0b1113ec56"
version = "6.5.3+0"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.RangeArrays]]
git-tree-sha1 = "b9039e93773ddcfc828f12aadf7115b4b4d225f5"
uuid = "b3c3ace0-ae52-54e7-9d0b-2c1406fd6b9d"
version = "0.3.2"

[[deps.RecipesBase]]
deps = ["PrecompileTools"]
git-tree-sha1 = "5c3d09cc4f31f5fc6af001c250bf1278733100ff"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.3.4"

[[deps.RecipesPipeline]]
deps = ["Dates", "NaNMath", "PlotUtils", "PrecompileTools", "RecipesBase"]
git-tree-sha1 = "45cf9fd0ca5839d06ef333c8201714e888486342"
uuid = "01d81517-befc-4cb6-b9ec-a95719d0359c"
version = "0.6.12"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "ffdaf70d81cf6ff22c2b6e733c900c3321cab864"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "1.0.1"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "3bac05bc7e74a75fd9cba4295cde4045d9fe2386"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.2.1"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "StaticArraysCore"]
git-tree-sha1 = "e2cc6d8c88613c05e1defb55170bf5ff211fbeac"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "1.1.1"

[[deps.Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[deps.Sixel]]
deps = ["Dates", "FileIO", "ImageCore", "IndirectArrays", "OffsetArrays", "REPL", "libsixel_jll"]
git-tree-sha1 = "2da10356e31327c7096832eb9cd86307a50b1eb6"
uuid = "45858cf5-a6b0-47a3-bbea-62219f50df47"
version = "0.1.3"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "5165dfb9fd131cf0c6957a3a7605dede376e7b63"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.2.0"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "e2cfc4012a19088254b3950b85c3c1d8882d864d"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.3.1"

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

    [deps.SpecialFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"

[[deps.StackViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "46e589465204cd0c08b4bd97385e4fa79a0c770c"
uuid = "cae243ae-269e-4f55-b966-ac2d0dc13c15"
version = "0.1.1"

[[deps.StaticArraysCore]]
git-tree-sha1 = "36b3d696ce6366023a0ea192b4cd442268995a0d"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.2"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.9.0"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1ff449ad350c9c4cbc756624d6f8a8c3ef56d3ed"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.7.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "1d77abd07f617c4868c33d4f5b9e1dbb2643c9cf"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.34.2"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "Pkg", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "5.10.1+6"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TiffImages]]
deps = ["ColorTypes", "DataStructures", "DocStringExtensions", "FileIO", "FixedPointNumbers", "IndirectArrays", "Inflate", "Mmap", "OffsetArrays", "PkgVersion", "ProgressMeter", "UUIDs"]
git-tree-sha1 = "34cc045dd0aaa59b8bbe86c644679bc57f1d5bd0"
uuid = "731e570b-9d59-4bfa-96dc-6df516fadf69"
version = "0.6.8"

[[deps.TranscodingStreams]]
git-tree-sha1 = "1fbeaaca45801b4ba17c251dd8603ef24801dd84"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.10.2"
weakdeps = ["Random", "Test"]

    [deps.TranscodingStreams.extensions]
    TestExt = ["Test", "Random"]

[[deps.URIs]]
git-tree-sha1 = "67db6cc7b3821e19ebe75791a9dd19c9b1188f2b"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.5.1"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[deps.Unitful]]
deps = ["Dates", "LinearAlgebra", "Random"]
git-tree-sha1 = "a72d22c7e13fe2de562feda8645aa134712a87ee"
uuid = "1986cc42-f94f-5a68-af5c-568840ba703d"
version = "1.17.0"

    [deps.Unitful.extensions]
    ConstructionBaseUnitfulExt = "ConstructionBase"
    InverseFunctionsUnitfulExt = "InverseFunctions"

    [deps.Unitful.weakdeps]
    ConstructionBase = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.UnitfulLatexify]]
deps = ["LaTeXStrings", "Latexify", "Unitful"]
git-tree-sha1 = "e2d817cc500e960fdbafcf988ac8436ba3208bfd"
uuid = "45397f5d-5981-4c77-b2b3-fc36d6e9b728"
version = "1.6.3"

[[deps.Unzip]]
git-tree-sha1 = "ca0969166a028236229f63514992fc073799bb78"
uuid = "41fe7b60-77ed-43a1-b4f0-825fd5a5650d"
version = "0.2.0"

[[deps.Vulkan_Loader_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Wayland_jll", "Xorg_libX11_jll", "Xorg_libXrandr_jll", "xkbcommon_jll"]
git-tree-sha1 = "2f0486047a07670caad3a81a075d2e518acc5c59"
uuid = "a44049a8-05dd-5a78-86c9-5fde0876e88c"
version = "1.3.243+0"

[[deps.Wayland_jll]]
deps = ["Artifacts", "EpollShim_jll", "Expat_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "7558e29847e99bc3f04d6569e82d0f5c54460703"
uuid = "a2964d1f-97da-50d4-b82a-358c7fce9d89"
version = "1.21.0+1"

[[deps.Wayland_protocols_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4528479aa01ee1b3b4cd0e6faef0e04cf16466da"
uuid = "2381bf8a-dfd0-557d-9999-79630e7b1b91"
version = "1.25.0+0"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Zlib_jll"]
git-tree-sha1 = "24b81b59bd35b3c42ab84fa589086e19be919916"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.11.5+0"

[[deps.XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[deps.XZ_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "cf2c7de82431ca6f39250d2fc4aacd0daa1675c0"
uuid = "ffd25f8a-64ca-5728-b0f7-c24cf3aae800"
version = "5.4.4+0"

[[deps.Xorg_libICE_jll]]
deps = ["Libdl", "Pkg"]
git-tree-sha1 = "e5becd4411063bdcac16be8b66fc2f9f6f1e8fe5"
uuid = "f67eecfb-183a-506d-b269-f58e52b52d7c"
version = "1.0.10+1"

[[deps.Xorg_libSM_jll]]
deps = ["Libdl", "Pkg", "Xorg_libICE_jll"]
git-tree-sha1 = "4a9d9e4c180e1e8119b5ffc224a7b59d3a7f7e18"
uuid = "c834827a-8449-5923-a945-d239c165b7dd"
version = "1.2.3+0"

[[deps.Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "afead5aba5aa507ad5a3bf01f58f82c8d1403495"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.8.6+0"

[[deps.Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6035850dcc70518ca32f012e46015b9beeda49d8"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.11+0"

[[deps.Xorg_libXcursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXfixes_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "12e0eb3bc634fa2080c1c37fccf56f7c22989afd"
uuid = "935fb764-8cf2-53bf-bb30-45bb1f8bf724"
version = "1.2.0+4"

[[deps.Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "34d526d318358a859d7de23da945578e8e8727b7"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.4+0"

[[deps.Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[deps.Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "0e0dc7431e7a0587559f9294aeec269471c991a4"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "5.0.3+4"

[[deps.Xorg_libXi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXfixes_jll"]
git-tree-sha1 = "89b52bc2160aadc84d707093930ef0bffa641246"
uuid = "a51aa0fd-4e3c-5386-b890-e753decda492"
version = "1.7.10+4"

[[deps.Xorg_libXinerama_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll"]
git-tree-sha1 = "26be8b1c342929259317d8b9f7b53bf2bb73b123"
uuid = "d1454406-59df-5ea1-beac-c340f2130bc3"
version = "1.1.4+4"

[[deps.Xorg_libXrandr_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "34cea83cb726fb58f325887bf0612c6b3fb17631"
uuid = "ec84b674-ba8e-5d96-8ba1-2a689ba10484"
version = "1.5.2+4"

[[deps.Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[deps.Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "8fdda4c692503d44d04a0603d9ac0982054635f9"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.1+0"

[[deps.Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "b4bfde5d5b652e22b9c790ad00af08b6d042b97d"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.15.0+0"

[[deps.Xorg_libxkbfile_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libX11_jll"]
git-tree-sha1 = "730eeca102434283c50ccf7d1ecdadf521a765a4"
uuid = "cc61e674-0454-545c-8b26-ed2c68acab7a"
version = "1.1.2+0"

[[deps.Xorg_xcb_util_cursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_jll", "Xorg_xcb_util_renderutil_jll"]
git-tree-sha1 = "04341cb870f29dcd5e39055f895c39d016e18ccd"
uuid = "e920d4aa-a673-5f3a-b3d7-f755a4d47c43"
version = "0.1.4+0"

[[deps.Xorg_xcb_util_image_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "0fab0a40349ba1cba2c1da699243396ff8e94b97"
uuid = "12413925-8142-5f55-bb0e-6d7ca50bb09b"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll"]
git-tree-sha1 = "e7fd7b2881fa2eaa72717420894d3938177862d1"
uuid = "2def613f-5ad1-5310-b15b-b15d46f528f5"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_keysyms_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "d1151e2c45a544f32441a567d1690e701ec89b00"
uuid = "975044d2-76e6-5fbe-bf08-97ce7c6574c7"
version = "0.4.0+1"

[[deps.Xorg_xcb_util_renderutil_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "dfd7a8f38d4613b6a575253b3174dd991ca6183e"
uuid = "0d47668e-0667-5a69-a72c-f761630bfb7e"
version = "0.3.9+1"

[[deps.Xorg_xcb_util_wm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "e78d10aab01a4a154142c5006ed44fd9e8e31b67"
uuid = "c22f9ab0-d5fe-5066-847c-f4bb1cd4e361"
version = "0.4.1+1"

[[deps.Xorg_xkbcomp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libxkbfile_jll"]
git-tree-sha1 = "330f955bc41bb8f5270a369c473fc4a5a4e4d3cb"
uuid = "35661453-b289-5fab-8a00-3d9160c6a3a4"
version = "1.4.6+0"

[[deps.Xorg_xkeyboard_config_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_xkbcomp_jll"]
git-tree-sha1 = "691634e5453ad362044e2ad653e79f3ee3bb98c3"
uuid = "33bec58e-1273-512f-9401-5d533626f822"
version = "2.39.0+0"

[[deps.Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "e92a1a012a10506618f10b7047e478403a046c77"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.5.0+0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+0"

[[deps.Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "49ce682769cd5de6c72dcf1b94ed7790cd08974c"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.5+0"

[[deps.eudev_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "gperf_jll"]
git-tree-sha1 = "431b678a28ebb559d224c0b6b6d01afce87c51ba"
uuid = "35ca27e7-8b34-5b7f-bca9-bdc33f59eb06"
version = "3.2.9+0"

[[deps.fzf_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "47cf33e62e138b920039e8ff9f9841aafe1b733e"
uuid = "214eeab7-80f7-51ab-84ad-2988db7cef09"
version = "0.35.1+0"

[[deps.gperf_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3516a5630f741c9eecb3720b1ec9d8edc3ecc033"
uuid = "1a1c6b14-54f6-533d-8383-74cd7377aa70"
version = "3.1.1+0"

[[deps.libaom_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3a2ea60308f0996d26f1e5354e10c24e9ef905d4"
uuid = "a4ae2306-e953-59d6-aa16-d00cac43593b"
version = "3.4.0+0"

[[deps.libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.8.0+0"

[[deps.libevdev_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "141fe65dc3efabb0b1d5ba74e91f6ad26f84cc22"
uuid = "2db6ffa8-e38f-5e21-84af-90c45d0032cc"
version = "1.11.0+0"

[[deps.libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[deps.libinput_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "eudev_jll", "libevdev_jll", "mtdev_jll"]
git-tree-sha1 = "ad50e5b90f222cfe78aa3d5183a20a12de1322ce"
uuid = "36db933b-70db-51c0-b978-0f229ee0e533"
version = "1.18.0+0"

[[deps.libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "94d180a6d2b5e55e447e2d27a29ed04fe79eb30c"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.38+0"

[[deps.libsixel_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Pkg", "libpng_jll"]
git-tree-sha1 = "d4f63314c8aa1e48cd22aa0c17ed76cd1ae48c3c"
uuid = "075b6546-f08a-558a-be8f-8157d0f608a5"
version = "1.10.3+0"

[[deps.libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "b910cb81ef3fe6e78bf6acee440bda86fd6ae00c"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+1"

[[deps.mtdev_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "814e154bdb7be91d78b6802843f76b6ece642f11"
uuid = "009596ad-96f7-51b1-9f1b-5ce2d5e8a71e"
version = "1.1.6+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.48.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"

[[deps.x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[deps.x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"

[[deps.xkbcommon_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll", "Wayland_protocols_jll", "Xorg_libxcb_jll", "Xorg_xkeyboard_config_jll"]
git-tree-sha1 = "9c304562909ab2bab0262639bd4f444d7bc2be37"
uuid = "d8fb68d0-12a3-5cfd-a85a-d49703b185fd"
version = "1.4.1+1"
"""

# ╔═╡ Cell order:
# ╠═ad405d72-2f5b-48c4-a729-5e3c2dc6b0fa
# ╠═6b914e30-84a1-11ee-1fbf-e9e3c597b367
# ╠═d47480aa-dac6-495c-914d-ac01e41adf00
# ╠═b2aadea1-c363-4a2b-ac41-e7968a21941c
# ╠═d46609b0-9f1f-42e2-8077-5dc70f63e750
# ╠═03351222-5867-4b68-bb91-0193ae553c8b
# ╠═3b638899-e765-4866-b015-f9ac17024490
# ╠═c8daa5f1-673c-4d18-b2fc-e99349b3d9f7
# ╠═ddce8d2a-9333-455b-bb38-8554f3c52953
# ╠═c7703d65-54bd-42e9-828c-86daee45206b
# ╠═0ca1f84e-c10f-42f5-99bf-50ef382d9b23
# ╠═591b1016-25fa-4105-abd7-07b623f28a25
# ╠═38da31b8-d574-46ad-a52e-346ff22c9b5b
# ╠═108ae3b2-7300-4a70-a3e6-ee57819dd372
# ╠═98e356ba-322f-4993-bab4-551e8bafcb02
# ╠═95ecaf8b-ab63-4579-8535-88418b06c7d5
# ╠═f170cead-41ba-4690-acfe-6bf58f4ad5e7
# ╠═98855c90-4e60-49a5-9685-f88036e45521
# ╠═b5c25c12-5a33-4e9b-90fa-f994ece17602
# ╠═eff40b96-1784-4e98-b327-40ac77af15b2
# ╠═3c49a223-ed4e-45c6-a701-4bd5abaf15b5
# ╠═6d0d50df-958a-4e11-86e7-20069058799b
# ╠═6093f46a-39ff-40b6-979b-b370ae91f19b
# ╠═e0c0c03e-44d6-4fac-9c6a-493a24673c3b
# ╠═80261586-4978-4701-95d4-89b2b465c22e
# ╠═b35869a3-ab7b-4d85-b379-b3b68b200f60
# ╠═ef678d53-0bcc-4b22-8a95-2240259ecf7e
# ╠═421a27ef-2cf7-4aca-a101-60862acfd2ad
# ╠═be010908-6411-4b08-a2d4-6bcc036e0322
# ╠═f1545d8c-ea95-4975-8d5f-81543545ff16
# ╠═f4709423-61a7-4cf0-b94d-0c79ccd53b64
# ╠═8ee2fd42-44a3-43e3-b757-abc0e0fc60ee
# ╠═c8b86a54-5c0f-4440-b488-1db8d8de7d3f
# ╠═05b49778-b296-4c9f-9b63-d8b7d4914ca6
# ╠═79a32dd6-bf2b-4368-aa68-e6b20116b1cb
# ╠═87969076-ae2e-4f3d-985c-fa01edaf90d1
# ╠═416a6f2a-6eac-4d0d-b714-f13aa62584ae
# ╠═e9b52bad-0d37-4a65-9396-551dc0437c25
# ╠═57b5129c-c748-4cdc-b1d3-50720c0d8a44
# ╠═0bec7954-a39b-4504-afe3-e493a3e1d267
# ╠═ab8e7da2-5963-4e8e-b0ca-33ce124d9ff7
# ╠═32d96b01-337c-4d14-8060-457f97795ed9
# ╠═ce8d18cc-0be5-4350-a9bb-c6e6d3d53938
# ╠═a3f48f4e-cb82-42ba-b640-5859a7efefdf
# ╠═ee95baee-97a9-4c00-acc1-31e45255bb4c
# ╠═d9070b9e-4e60-4ad7-ae53-4c43a7c77557
# ╠═76708ffa-8040-42e5-add0-67ae4b60a233
# ╠═f98f648b-1f3b-4cf9-9445-e34263378c84
# ╠═93e0cc64-9a71-455d-bbca-eea12e238dcd
# ╠═69ad9d11-9c92-4e96-a3d3-13a644b0ee0b
# ╠═19ad92cd-071a-49a9-a119-6577a157a475
# ╠═8e81e078-8117-43b2-b40d-94b91edbc393
# ╠═7443c66b-b709-4c37-860f-06f5eccf31a9
# ╠═119c1e0c-57d9-4aa6-a720-ed8d4d0ad314
# ╠═840d2be9-8fde-449c-a121-35efc9a8de90
# ╠═fa95d864-fe82-4996-9bbd-ad32a968212f
# ╠═b77af2d9-68c0-447e-abf9-5bc8fccbbfe4
# ╠═d904528a-559d-450c-a0f2-60926933d6db
# ╠═36f92b7f-66c1-4b6a-b4e3-8216a46ba022
# ╠═260e99fe-11e2-4d80-8d3c-3affdce0265e
# ╠═691fd46d-bfad-44a1-8f54-b41c8e878662
# ╠═539d901a-f350-4b74-a8a9-896a810f4105
# ╠═40ee0706-cd63-424c-ae26-8f7fe97d6748
# ╠═6b8ac421-c52f-4048-90c4-7e2360263670
# ╠═b7b759ef-6237-43b5-9ff2-f051c392fdd3
# ╠═ce6ea415-d522-495f-8395-3c017befaa9f
# ╠═df61265a-d69e-4b0e-a0bc-d24e3dadbb85
# ╠═3e862e9d-2e06-493f-92fd-1e74371a77eb
# ╠═4af6a1e2-1222-497b-8d2c-925c9b768991
# ╠═7aa0eb45-d2bb-4bbd-91b7-59702a76cf0e
# ╠═9269927a-99c2-42e5-a7a4-24e3f27a01e5
# ╠═e489a5b7-ad68-4299-b9a7-799df7722aff
# ╠═823f0e7d-f14d-40e5-a2a0-e03619d61f62
# ╠═ec01326e-cdc7-49e3-8b11-30b71c755421
# ╠═1fdc0843-b808-4d3c-8696-accf3345fc82
# ╠═a7b90a6a-6296-4d76-bae7-28d63f9321f9
# ╠═453bda0f-9dbd-477e-a5b4-a6d94d95cdf0
# ╠═12a2792e-6cd0-4aca-bd49-9f74242d0286
# ╠═6d3c060e-508f-45b4-a224-d641c88b3198
# ╠═2afa3290-d955-4cbc-a8fc-c2591be9fbe4
# ╠═a4b34899-5439-4393-b3e5-beb4b9b89751
# ╠═5d7b325b-b051-47f8-ba8d-408bfd4cbac1
# ╠═eb367bc6-d678-482a-857a-456b462a895b
# ╠═f79b2f14-32a5-4653-adfa-dbde382a00c8
# ╠═49f35353-877c-4510-8746-c87ecd7dc074
# ╠═84393a04-bb71-46f5-a8fc-ffcb69ce56e9
# ╠═841a870a-4a15-4d7f-8b63-5a0139600f37
# ╠═f07fe636-87a4-4e91-8073-af5a7fa6803e
# ╠═1850d59e-3985-46ed-8dcf-67226ae39324
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
