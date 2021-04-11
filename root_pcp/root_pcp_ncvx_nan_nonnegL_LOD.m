function [L_final, S_final] = root_pcp_ncvx_nan_nonnegL_LOD (D, lambda, mu, r, Delta)
% [L_final, S_final] = root_pcp_with_nan_nonnegL_LOD( D, lambda, mu, Delta )
% use NaN for missing entries in D, assume that the true L>=0, and the
% observation D>=0 
% use -1 for below LOD
% 
% LOD penalty: 
% f(x,y) = (x-y)^2 if y>0
%        = (x-Delta)^2 if y=-1, x>Delta
%        = x^2 if y=-1, x<0
%        = 0 otherwise
% 
% Solve the following problem:
% min_{L,S}
%         ||L||_* + lambda * ||S||_1 + mu * (\sum_{ij observed} f((L+S)_ij,D_ij))^0.5 +
%         I{L>=0}
% This is first transformed to the problem
% min_{L1,L2,S,Z}
%      ||L1||_* + lambda * ||S1||_1 + mu * (\sum_{ij observed} f(Z_ij,D_ij))^0.5 + I{L3>=0}
% s.t. L1 = L2
%      S1 = S2
%      Z = P_obs[ L2 + S2]
%      L1 = L3
% The algorithm conducts ADMM splitting as (L1, S1, Z), (L2, S2, L3).

[n,p] = size(D);
rho = 0.1; % Augmented Lagrangian parameter

[L1, L2, L3, S1, S2, Z, Y1, Y2, Y3, Y4] = deal(zeros(n,p));

mask_above_lod = (D>=0);
mask_below_lod = (D<0);
mask_obs = ~isnan(D);
D(~mask_obs) = -2;


MAX_ITER = 20000;
EPS_ABS = 1e-6;
EPS_REL = 1e-6;

flag_converge = 0;

% ADMM-splitting iterations
for i = 1:MAX_ITER
    L2_old = L2;
    S2_old = S2;
    L3_old = L3;
    
    L1 = proj_rank_r( (L2+L3-Y1/rho-Y4/rho)/2,r );
    S1 = prox_l1( S2-Y2/rho, lambda/rho );
    
    temp = L2+S2-Y3/rho;
    temp_D = D.*mask_above_lod+temp.*(mask_below_lod & (temp>=0) & (temp<=Delta))+Delta.*(mask_below_lod & (temp>Delta));
    Z = prox_fro( temp - temp_D, mu/rho )+temp_D;
%     Z_unobs = 0;
%     Z_obs_below_LOD1 = (mask_below_lod & (temp>=0) & (temp<=Delta)).*temp;
%     
%     temp2 = mask_obs.*(1-(mask_below_lod & (temp>=0) & (temp<=Delta))).*temp - mask_above_lod.*D - Delta*mask_below_lod.*(temp>=Delta);
%     Z = prox_fro( temp2, mu/rho )+mask_above_lod.*D +Delta*mask_below_lod.*(temp>=Delta)+Z_unobs+Z_obs_below_LOD1;
    
    L3 = max(L1+Y4/rho,0);
% % % % %     % Update 2nd primal variable (L2,S2)
    L2_obs = mask_obs.*(1/3*( 2*L1-S1+Z + (2*Y1-Y2+Y3)/rho ));
    L2_unobs = (1-mask_obs).*(L1+Y1/rho);
    L2 = L2_obs+L2_unobs;
    
    S2_obs = mask_obs.*(1/3*( 2*S1-L1+Z + (2*Y2-Y1+Y3)/rho ));
    S2_unobs = (1-mask_obs).*(S1+Y2/rho);
    S2 = S2_obs+S2_unobs;

    
    % Update dual variable (Y1,Y2)
    Y1 = Y1 + rho*(L1-L2);
    Y2 = Y2 + rho*(S1-S2);
    Y3 = Y3 + rho*mask_obs.*(Z-(L2 + S2));
    Y4 = Y4 + rho*(L1-L3);
    
    %  Calculate primal & dual residuals; Update rho
    res_primal = sqrt(norm(L1-L2,'fro')^2 + norm(S1-S2,'fro')^2+norm(mask_obs.*(Z-L2-S2),'fro')^2+norm(L1-L3,'fro')^2);
    res_dual = rho * sqrt( norm(L2+L3-L2_old-L3_old,'fro')^2 + norm(S2-S2_old,'fro')^2 + ...
                           norm(mask_obs.*(L2-L2_old+S2-S2_old),'fro')^2 );
    
    if res_primal > 10 * res_dual
        rho = rho * 2;
    elseif res_dual > 10 * res_primal
        rho = rho / 2;
    end

% Check stopping criteria

    thresh_primal = EPS_ABS * sqrt(4*n*p) + EPS_REL * ...
                    max([sqrt( 2*norm(L1,'fro')^2 + norm(S1,'fro')^2 + norm(Z,'fro')^2 ), ...
                         sqrt( norm(L2,'fro')^2 + norm(S2,'fro')^2 + norm(mask_obs.*(L2+S2),'fro')^2 +norm(L3,'fro')^2)]);                
    thresh_dual = EPS_ABS * sqrt(3*n*p) + EPS_REL * ...
                    sqrt( norm(Y1+Y4,'fro')^2 + norm(Y2,'fro')^2 + norm(Y3,'fro')^2  );
    if res_primal < thresh_primal && res_dual < thresh_dual
        flag_converge = 1;
        disp(['Converged in ',num2str(i),' iterations.']);
        break
    end
end

L_final = (L1+L2+L3) / 3;
S_final = (S1+S2)/2;
if flag_converge == 0
    disp('Did not converge.');
end


return

