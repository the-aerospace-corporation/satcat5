function [xy] = draw_satcat5(scale, tau, print)
%DRAW_SATCAT5 Draw "SatCat5" mascot using an XY-raster
% xy = draw_satcat5([scale], [tau], [print])
%   scale   = (Optional) Integer scaling over [-N..+N] each axis
%             If this argument is omitted, scale is [0..1] each axis
%   tau     = (Optional) Simulate low-pass filter
%             Argument gives the time constant, measured in samples
%   print   = (Optional) Print raw coefficients just after [scale] step

% Copyright 2021 The Aerospace Corporation.
% This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

% A quarter, half, or full circle with N points:
% (Each one starts from the +X axis and spans; multiply by phasor as needed.)
cirq = @(n) exp(1j*linspace(0, pi/2, n));   % Includes both endpoints
cirh = @(n) exp(1j*linspace(0, pi,   n));   % Includes both endpoints
circ = @(n) exp(1j*linspace(0, 2*pi, n));   % Start/end are duplicates

% Segments for the body outline.
cl  = linspace(1.00j, 0.15j, 20);           % Left (from top)
cb1 = (0.15 + 0.15j) - 0.15 * cirq(8);      % Bottom (from left)
cb2 = linspace(0.15, 0.30, 6);
cb3 = (0.30 + 0.15j) - 0.15j * cirq(8);
cr  = fliplr(cl) + 0.45;                    % Right (from bottom)
ct1 = linspace(0.45+1.00j, 0.32+0.82j, 7);  % Top (from right)
ct2 = linspace(0.32+0.82j, 0.13+0.82j, 7);
ct3 = linspace(0.13+0.82j, 1.00j, 7);

% Segments for the face.
cw1 = linspace(0.05+0.70j, 0.12+0.70j, 4);  % Top-left whisker
cw2 = cw1 - 0.04j;
cw3 = cw2 - 0.04j;
cw4 = complex(0.45 - real(cw1), imag(cw1)); % Top-right whisker
cw5 = cw4 - 0.04j;
cw6 = cw5 - 0.04j;
cf1 = (0.19 + 0.72j) + 0.02j * circ(7);     % Left eye
cf2 = (0.20 + 0.64j) - 0.0225 * cirh(5);    % Mouth (left half)
cf3 = (0.225 + 0.65j) + 0.01 * circ(5);     % Nose
cf4 = (0.25 + 0.64j) - 0.0225 * cirh(5);    % Mouth (right half)
cf5 = (0.26 + 0.72j) + 0.02j * circ(7);     % Right eye

% Segments for the tail.
tt1 = linspace(0.32, 0.75, 14);                 % Base
tt2 = (0.75 + 0.25j) + 0.25 * exp(1j*linspace(-pi/2, +pi*0.7, 30));
tt3 = linspace(0.58 + 0.43j, 0.58 + 0.82j, 10);
tt4 = linspace(0.58 + 0.82j, 1.00 + 0.82j, 13); % Tip
tt  = [tt1(2:end), tt2(2:end), tt3(1:end), tt4(2:end)];

% Concatenate everything together:
xy = [ ...
    cb3(2:end), cr(2:end), ...              % Start from base of tail
    ct1(2:end), ct2(2:4), ...               % First half of top
    cf1, cw1, fliplr(cw2), cw3, ...         % Left eye and whiskers
    cf2(1:end-1), cf3, cf4(2:end), ...      % Mouth and nose
    cw6, fliplr(cw5), cw4, cf5, ...         % Right whiskers and eye
    ct2(4:end), ct3(2:end), ...             % Second half of top
    cl(2:end), cb1(2:end), cb2(2:end), ...  % Left and bottom
    tt(1:2:end), ...                        % Tail (base to tip)
    tt(end:-2:1), ...                       % Tail (retrace)
];

% Re-scale to the specified range?
if (exist('scale','var') && ~isempty(scale))
    xy = round((2*xy - (1+1j)) * scale);
end

% Print the coefficients?
if (exist('print','var') && print)
    for n = 1:length(xy)
        fprintf('%6d, %6d,\n', real(xy(n)), imag(xy(n)));
    end
end

% Simulate a low-pass filter?
if (exist('tau','var') && ~isempty(tau))
    up = 100;                               % Upsampling factor
    xu = upsample(xy, up);
    g  = 1 - 1 / exp(1/(up*tau));           % Forgetting factor (gamma)
    p  = [ones(1,up), zeros(1,10*up)];      % Upsampled square pulse
    h  = filter(g, [1, g-1], p);            % Apply 1st-order filter
    xy = cconv(h, xu, length(xu));          % Circular convolution
end

end
