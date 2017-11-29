function [LinearFilter] = getLinearFilterOnline(stimulus,response, samplerate, freqcutoff)

% this function will find the linear filter that changes row vector "signal" 
% into a set of "responses" in rows.  "samplerate" and "freqcuttoff" 
% (which should be the highest frequency in the signal) should be in HZ.

% The linear filter is a cc normalized by the power spectrum of the signal
% JC 3/31/08
%MHT 080814

%for rows as trials
FilterFft = mean((fft(response,[],2).*conj(fft(stimulus,[],2))),1)./mean(fft(stimulus,[],2).*conj(fft(stimulus,[],2)),1) ;

freqcutoff_adjusted = round(freqcutoff/(samplerate/length(stimulus))) ; % this adjusts the freq cutoff for the length
FilterFft(:,1+freqcutoff_adjusted:length(stimulus)-freqcutoff_adjusted) = 0 ; 

LinearFilter = real(ifft(FilterFft)) ;

end