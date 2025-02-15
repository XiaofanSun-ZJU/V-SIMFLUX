function [zvals,Wrms] = set_saffocus(params)
% This function finds the stage positions for optimal focus in SAF
% conditions by optimizing the Strehl ratio.
% The Strehl ratio is computed for 10 z-planes around an initial estimate of
% the stage position (-1.25*refimm/refmed*depth). Then a second order
% polynomial fit is performed near the maximum to achieve subsampling
% z-precision.
% The Wrms due to the refractive index mismatch is then computed by
% Wrms = lambda/(2*pi)*log(1/S(Wab + Wri|Wab)), with S(Wab|Wab + Wri) the ratio
% of the maximum intensity of PSF with aberration Wab and the maximum intensity
% of PSF with additional aberration Wab ?nd refrective index mismatch Wri.
%
% Note: for depth = 0 (at the coverslip) the Wrms becomes negative as
% maximum intensity is no longer at z-stage position = 0;
%
% relevant z-positions:
% zvals = [nominal stage position, free working distance, -image depth from cover slip]

% Marijn Siemons, 16 04 2018

NA = params.NA;
refmed = params.refmed;
refcov = params.refcov;
refimm = params.refimm;
refimmnom = params.refimmnom;
lambda = params.lambda;
Npupil = params.Npupil;

zvals = [0 params.fwd -params.depth];

% pupil radius (in diffraction units) and pupil coordinate sampling
PupilSize = 1.0;
DxyPupil = 2*PupilSize/Npupil;
XYPupil = -PupilSize+DxyPupil/2:DxyPupil:PupilSize;
[YPupil,XPupil] = meshgrid(XYPupil,XYPupil);

% calculation of relevant Fresnel-coefficients for the interfaces
% between the medium and the cover slip and between the cover slip
% and the immersion fluid
% The Fresnel-coefficients should be divided by the wavevector z-component
% of the incident medium, this factor originates from the
% Weyl-representation of the emitted vector spherical wave of the dipole.

% CosThetaMed = sqrt(1-(XPupil.^2+YPupil.^2)*NA^2/refmed^2);
argMed = 1-(XPupil.^2+YPupil.^2)*NA^2/refmed^2;
phiMed = atan2(0,argMed);
CosThetaMed = sqrt(abs(argMed)).*(cos(phiMed/2)-1j*sin(phiMed/2));
CosThetaCov = sqrt(1-(XPupil.^2+YPupil.^2)*NA^2/refcov^2);
CosThetaImm = sqrt(1-(XPupil.^2+YPupil.^2)*NA^2/refimm^2);
CosThetaImmnom = sqrt(1-(XPupil.^2+YPupil.^2)*NA^2/refimmnom^2);

FresnelPmedcov = 2*refmed*CosThetaMed./(refmed*CosThetaCov+refcov*CosThetaMed);
FresnelSmedcov = 2*refmed*CosThetaMed./(refmed*CosThetaMed+refcov*CosThetaCov);
FresnelPcovimm = 2*refcov*CosThetaCov./(refcov*CosThetaImm+refimm*CosThetaCov);
FresnelScovimm = 2*refcov*CosThetaCov./(refcov*CosThetaCov+refimm*CosThetaImm);
FresnelP = FresnelPmedcov.*FresnelPcovimm;
FresnelS = FresnelSmedcov.*FresnelScovimm;

% setting of vectorial functions
Phi = atan2(YPupil,XPupil);
CosPhi = cos(Phi);
SinPhi = sin(Phi);
CosTheta = CosThetaMed; % sqrt(1-(XPupil.^2+YPupil.^2)*NA^2/refmed^2);
SinTheta = sqrt(1-CosTheta.^2);

pvec(:,:,1) = FresnelP.*CosTheta.*CosPhi;
pvec(:,:,2) = FresnelP.*CosTheta.*SinPhi;
pvec(:,:,3) = -FresnelP.*SinTheta;
svec(:,:,1) = -FresnelS.*SinPhi;
svec(:,:,2) = FresnelS.*CosPhi;
svec(:,:,3) = 0;

% PolarizationVector = zeros(Npupil,Npupil,2,3);
PolarizationVector(:,:,1,:) = CosPhi.*pvec-SinPhi.*svec;
PolarizationVector(:,:,2,:) = SinPhi.*pvec+CosPhi.*svec;

% definition aperture
ApertureMask = double((XPupil.^2+YPupil.^2)<1.0);

% aplanatic amplitude factor
Amplitude = ApertureMask.*sqrt(CosThetaImm)./(refmed*CosThetaMed);

Strehlnorm = 0;
for itel = 1:2
    for jtel = 1:3
        Strehlnorm = Strehlnorm + abs(sum(sum(Amplitude.*exp(2*pi*1i).*PolarizationVector(:,:,itel,jtel)))).^2;
    end
end

Nz = 101;
zpos = linspace(3/2*params.zspread(1),3/2*params.zspread(2),Nz);
Strehl = zeros(1,Nz);
for jz = 1:Nz
    zvals(1) = params.fwd - 1.25*refimm/refmed*params.depth + zpos(jz);
    Wzpos = zvals(1)*refimm*CosThetaImm-zvals(2)*refimmnom*CosThetaImmnom-zvals(3)*refmed*CosThetaMed;
    Wzpos = Wzpos.*ApertureMask;
    for itel = 1:2
        for jtel = 1:3
            Strehl(jz) = Strehl(jz) + abs(sum(sum(Amplitude.*exp(2*pi*1i*Wzpos/lambda).*PolarizationVector(:,:,itel,jtel)))).^2./Strehlnorm;
        end
    end
end
[~, indz] = max(Strehl);
if indz <= 3; indz = 3; elseif indz > (Nz-3); indz = Nz-3; end
zfit = polyfit(zpos(indz-2:indz+2),Strehl(indz-2:indz+2),2);
zvals(1) = params.fwd - 1.25*refimm/refmed*params.depth - zfit(2)/(2*zfit(1));

MaxStrehl = polyval(zfit,- zfit(2)/(2*zfit(1)));
Wrms = lambda/(2*pi)*log(1/MaxStrehl);

% output relevant numbers
if params.debugmode
    fprintf('image plane depth from cover slip = %4.0f nm\n',-zvals(3))
    fprintf('free working distance = %6.3f mu\n',1e-3*zvals(2))
    fprintf('nominal z-stage position = %6.3f mu\n',1e-3*zvals(1))
    fprintf('rms aberration due to RI mismatch = %4.1f mlambda\n',1e3*Wrms/params.lambda)
    
    figure
    plot(zpos - 1.25*refimm/refmed*params.depth,Strehl)
    xlabel('Stage position')
    ylabel('Strehl')
end

end