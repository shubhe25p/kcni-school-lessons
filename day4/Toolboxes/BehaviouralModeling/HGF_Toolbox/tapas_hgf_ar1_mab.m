function [traj, infStates] = tapas_hgf_ar1_mab(r, p, varargin)
% Calculates the trajectories of the agent's representations under the AR(1)-HGF in a multi-armed
% bandit task
%
% This function can be called in two ways:
% 
% (1) tapas_hgf_ar1_mab(r, p)
%   
%     where r is the structure generated by tapas_fitModel and p is the parameter vector in native space;
%
% (2) tapas_hgf_ar1_mab(r, ptrans, 'trans')
% 
%     where r is the structure generated by tapas_fitModel, ptrans is the parameter vector in
%     transformed space, and 'trans' is a flag indicating this.
%
% --------------------------------------------------------------------------------------------------
% Copyright (C) 2013 Christoph Mathys, TNU, UZH & ETHZ
%
% This file is part of the HGF toolbox, which is released under the terms of the GNU General Public
% Licence (GPL), version 3. You can redistribute it and/or modify it under the terms of the GPL
% (either version 3 or, at your option, any later version). For further details, see the file
% COPYING or <http://www.gnu.org/licenses/>.


% Transform paramaters back to their native space if needed
if ~isempty(varargin) && strcmp(varargin{1},'trans');
    p = tapas_hgf_ar1_mab_transp(r, p);
end

% Number of levels
try
    l = r.c_prc.n_levels;
catch
    l = length(p)/6;
    
    if l ~= floor(l)
        error('Cannot determine number of levels');
    end
end

% Number of bandits
try
    b = r.c_prc.n_bandits;
catch
    error('Number of bandits has to be configured in r.c_prc.n_bandits.');
end

% Unpack parameters
mu_0 = p(1:l);
sa_0 = p(l+1:2*l);
phi  = p(2*l+1:3*l);
m    = p(3*l+1:4*l);
ka   = p(4*l+1:5*l-1);
om   = p(5*l:6*l-2);
th   = p(6*l-1);
al   = p(6*l);

% Add dummy "zeroth" trial
u = [0; r.u(:,1)];
y = [0; r.u(:,2)];

% Number of trials (including prior)
n = size(u,1);

% Construct time axis
if r.c_prc.irregular_intervals
    if size(u,2) > 1
        t = [0; r.u(:,end)];
    else
        error('Input matrix must contain more than one column if irregular_intervals is set to true.');
    end
else
    t = ones(n,1);
end

% Initialize updated quantities

% Representations
mu = NaN(n,l,b);
pi = NaN(n,l,b);

% Other quantities
muhat = NaN(n,l,b);
pihat = NaN(n,l,b);
w     = NaN(n,l-1);
da    = NaN(n,l-1);
dau   = NaN(n,1);

% Representation priors
% Note: first entries of the other quantities remain
% NaN because they are undefined and are thrown away
% at the end; their presence simply leads to consistent
% trial indices.
mu(1,:,:) = repmat(mu_0,[1 1 b]);
pi(1,:,:) = repmat(1./sa_0,[1 1 b]);

% Representation update loop
% Pass through trials 
for k = 2:1:n
    if not(ismember(k-1, r.ign))
        %%%%%%%%%%%%%%%%%%%%%%
        % Effect of input u(k)
        %%%%%%%%%%%%%%%%%%%%%%
        
        % 1st level
        % ~~~~~~~~~
        % Prediction
        muhat(k,1,:) = mu(k-1,1,:) +t(k) *phi(1) *(m(1) -mu(k-1,1,:));
        
        % Precision of prediction
        pihat(k,1,:) = 1/(1/pi(k-1,1,:) +t(k) *exp(ka(1) *mu(k-1,2,:) +om(1)));
        
        % Input prediction error
        dau(k) = u(k) -muhat(k,1,y(k));
        
        % Updates
        pi(k,1,:) = pihat(k,1,:);
        pi(k,1,y(k)) = pi(k,1,y(k)) +1/al;
        
        mu(k,1,:) = muhat(k,1,:);
        mu(k,1,y(k)) = mu(k,1,y(k)) +1/pihat(k,1,y(k)) *1/(1/pihat(k,1,y(k)) +al) *dau(k);

        % Volatility prediction error
        da(k,1) = (1/pi(k,1,y(k)) +(mu(k,1,y(k)) -muhat(k,1,y(k)))^2) *pihat(k,1,y(k)) -1;
        
        if l > 2
            % Pass through higher levels
            % ~~~~~~~~~~~~~~~~~~~~~~~~~~
            for j = 2:l-1
                % Prediction
                muhat(k,j,:) = mu(k-1,j,:) +t(k) *phi(j) *(m(j) -mu(k-1,j,:));
                
                % Precision of prediction
                pihat(k,j,:) = 1/(1/pi(k-1,j,:) +t(k) *exp(ka(j) *mu(k-1,j+1,:) +om(j)));

                % Weighting factor
                w(k,j-1) = t(k) *exp(ka(j-1) *mu(k-1,j,y(k)) +om(j-1)) *pihat(k,j-1,y(k));

                % Updates
                pi(k,j,:) = pihat(k,j,:) +1/2 *ka(j-1)^2 *w(k,j-1) *(w(k,j-1) +(2 *w(k,j-1) -1) *da(k,j-1));

                if pi(k,j,1) <= 0
                    error('Negative posterior precision. Parameters are in a region where model assumptions are violated.');
                end

                mu(k,j,:) = muhat(k,j,:) +1/2 *1/pi(k,j,:) *ka(j-1) *w(k,j-1) *da(k,j-1);
    
                % Volatility prediction error
                da(k,j) = (1/pi(k,j,y(k)) +(mu(k,j,y(k)) -muhat(k,j,y(k)))^2) *pihat(k,j,y(k)) -1;
            end
        end

        % Last level
        % ~~~~~~~~~~
        % Prediction
        muhat(k,l,:) = mu(k-1,l,:) +t(k) *phi(l) *(m(l) -mu(k-1,l,:));
        
        % Precision of prediction
        pihat(k,l,:) = 1/(1/pi(k-1,l,:) +t(k) *th);

        % Weighting factor
        w(k,l-1) = t(k) *exp(ka(l-1) *mu(k-1,l,y(k)) +om(l-1)) *pihat(k,l-1,y(k));
        
        % Updates
        pi(k,l,:) = pihat(k,l,:) +1/2 *ka(l-1)^2 *w(k,l-1) *(w(k,l-1) +(2 *w(k,l-1) -1) *da(k,l-1));

        if pi(k,l,1) <= 0
            error('Negative posterior precision. Parameters are in a region where model assumptions are violated.');
        end

        mu(k,l,:) = muhat(k,l,:) +1/2 *1/pi(k,l,:) *ka(l-1) *w(k,l-1) *da(k,l-1);
    
        % Volatility prediction error
        da(k,l) = (1/pi(k,l,y(k)) +(mu(k,l,y(k)) -muhat(k,l,y(k)))^2) *pihat(k,l,y(k)) -1;
    else

        mu(k,:,:) = mu(k-1,:,:);
        pi(k,:,:) = pi(k-1,:,:);

        muhat(k,:,:) = muhat(k-1,:,:);
        pihat(k,:,:) = pihat(k-1,:,:);
        
        w(k,:)  = w(k-1,:);
        da(k,:) = da(k-1,:);
        
    end
end

% Remove representation priors
mu(1,:,:)  = [];
pi(1,:,:)  = [];

% Check validity of trajectories
if any(isnan(mu(:))) || any(isnan(pi(:)))
    error('Variational approximation invalid. Parameters are in a region where model assumptions are violated.');
end

% Remove other dummy initial values
muhat(1,:,:) = [];
pihat(1,:,:) = [];
w(1,:)       = [];
da(1,:)      = [];
dau(1)       = [];

% Create result data structure
traj = struct;

traj.mu     = mu;
traj.sa     = 1./pi;

traj.muhat  = muhat;
traj.sahat  = 1./pihat;

traj.w      = w;
traj.da     = da;
traj.dau    = dau;

% Create matrices for use by observation model
infStates = NaN(n-1,l,b,2);
infStates(:,:,:,1) = traj.muhat;
infStates(:,:,:,2) = traj.sahat;

return;
