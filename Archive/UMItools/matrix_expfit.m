function out=matrix_expfit(incube,taxis,varargin)
%fits an exponential decay to a 3d or 4d data set, last dimension is time
%out=matrix_expfit(incube,taxis [,'oddeven','errpoke])
%incube: size(nro npe numel(taxis)) is a stack of single slice images acquired at different times
%
%'oddeven' takes the running average of odd and even echoes to kill odd even asymmetry
%'errpoke' is a development option to return deviation to the base
%workspace

%out is structure with fields 'amplitude' and 'tau', 'chi2', result of a
%pixelwise fit

options=varargin;


%sort by ascending times
[taxis, indvec]=sort(taxis);
if ndims(incube)==3;
    incube=incube(:,:,indvec);
    [ny nx ntimes]=size(incube);
    nsl=1;
elseif ndims(incube)==4;
    incube=incube(:,:,:,indvec);
    [ny nx nsl ntimes]=size(incube);
end


if ntimes~=numel(taxis);
    display('matrix_expfit: timeaxis has to match number of echoes in incube!')
    return
end

%option to fit to an average of adjacent echoes, to smooth out oddeven variability %
if any(strcmp(varargin, 'oddeven'));
    if ndims(incube) == 3,
        newincube=zeros(ny,nx,ntimes-1);
        newtaxis=zeros(1,ntimes-1);
        for jj=1:ntimes-1;
            newincube(:,:,jj)=exp((log(incube(:,:,jj))+log(incube(:,:,jj+1)))/2);
            newtaxis(jj)=(taxis(jj)+taxis(jj+1))/2;
        end
        incube=newincube;
        taxis=newtaxis;
    elseif ndims(incube) == 4;
        newincube=zeros(ny,nx,nsl,ntimes-1);
        newtaxis=zeros(1,ntimes-1);
        for jj=1:ntimes-1;
            newincube(:,:,:,jj)=exp((log(incube(:,:,:,jj))+log(incube(:,:,:,jj+1)))/2);
            newtaxis(jj)=(taxis(jj)+taxis(jj+1))/2;
        end
        incube=newincube;
        taxis=newtaxis;
    end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%estimate the image noiselevel
noiselevel=estimate_noiselevel(incube); 

%single slice multiecho
if ndims(incube) == 3;
    %third dimension is the echotime dimension
    [amplitude, Tau, err_amplitude,err_Tau,chi2]=matrix_fit(abs(incube),taxis,noiselevel,options{:});
    nosl=1;
end

%multislice multiecho
if ndims(incube) == 4;
    %third dimension is the slice dimension
    %fourth dimension is the echo time dimension
    sincube=size(incube);
    nosl=sincube(3);
    amplitude=zeros(sincube(1:3));
    Tau=amplitude;
    err_amplitude=amplitude;
    err_Tau=Tau;
    
    Rate=(zeros(sincube(1:3)));
    for ns=1:nosl;
        [amplitude(:,:,ns), Tau(:,:,ns), err_amplitude(:,:,ns),err_Tau(:,:,ns)] = ...
            matrix_fit(squeeze(incube(:,:,ns,:)),taxis,noiselevel,options{:});
    end
    chi2=0;
end

out.amplitude=amplitude;
out.Tau=Tau;
out.error.amplitude=err_amplitude;
out.error.Tau=err_Tau;
out.error.chi2=chi2;


function [amplitude, tau, err_amplitude,err_Tau,errout] = matrix_fit(incube,taxis,noiselevel,varargin)
% this routine fits the log of the signal to a line
% log(y) = log(a) + bt
% [amplitude, tau, err_amplitude,err_Tau] = matrix_fit(incube,taxis,noiselevel)
% noiselevel can either be a scalar or a cube of the same size as the input
% data
% the third dimension of the input cube has length numel(taxis)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%check if there is a time limit 
ind=find(strcmp(varargin,'tlim'));
if ~isempty(ind)
    tfitlimit=varargin{ind+1};
    tindvec=find(taxis<=tfitlimit);
else
    tindvec=1:numel(taxis);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% check if the noise level has the proper form, scalar or the same size as incube
if ~(numel(incube)==numel(noiselevel));
    if isscalar(noiselevel);
        noiselevel=noiselevel*ones(size(incube));
    else
        display('noiselevel must be scalar or an array of the same size as the input data.');
        return
    end
end


oneovers2 = (abs(incube(:,:,tindvec))./noiselevel(:,:,tindvec)).^2; %scale noise to account for change of variables to log(y);
sincube=size(incube(:,:,tindvec));

y=log(abs(incube));

x=ones(sincube);
for jj=1:sincube(3);
    x(:,:,jj)=x(:,:,jj)*taxis(jj);
end

xy=x.*y(:,:,tindvec);
x2=x.*x;

Sx2=sum(x2.*oneovers2,3);
Sy=sum(y(:,:,tindvec).*oneovers2,3);
Sx=sum(x.*oneovers2,3);
Sxy=sum(xy.*oneovers2,3);
Soneovers2=sum(oneovers2,3);

Delta=Soneovers2.*Sx2-Sx.^2;
b= (Soneovers2.*Sxy - Sx.*Sy)./Delta;
a= (Sx2.*Sy-Sx.*Sxy)./Delta;

amplitude=exp(a);
tau=-1./b;

%errors on the logs:
sigma_a_squared=Delta.^(-1).*Sx2;
sigma_b_squared=Delta.^(-1).*Soneovers2;

%errors in the parameters, as a fraction of the value
err_amplitude=sqrt(sigma_a_squared);
err_Tau=sqrt(sigma_b_squared)./abs(b.^2);
    

%chi2 pixel by pixel
synthdata=zeros(size(incube));
sincube=size(incube);

oneovers2 = (abs(incube)./noiselevel).^2;

for jj=1:sincube(3);
    synthdata(:,:,jj)=a+b*taxis(jj);
end

errout.data=y;
errout.noise=sqrt(1./oneovers2);
errout.fit=synthdata;
errout.taxis=taxis;
errout.chi2=sum((synthdata-y).^2.*oneovers2,3)/(numel(taxis)-2);
errout.dev2=sum((synthdata-y).^2,3)/(numel(taxis)-2);

if any(strcmp(varargin,'errpoke'));
    assignin('base','err',errout);
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function noiselevel=estimate_noiselevel(incube)
%estimate the noise using NxN patches of the last echo
N=10;
lastecho=incube(:,:,end);
si=size(lastecho);
ni=floor(si(1)/N);
nj=floor(si(2)/N);
noisetest=zeros(ni,nj);
for ii=0:ni-1;
    for jj=0:nj-1;
        ivec=(1:N) + ii*N;
        jvec=(1:N) + jj*N;
        patch=lastecho(ivec,jvec);
        noisetest(ii+1,jj+1)=sqrt(var(real(patch(:)))+var(imag(patch(:))));
    end
end

noiselevel=sort(noisetest(:));
noiselevel=sqrt(2)*mean(noiselevel(1:round(numel(noiselevel)/2)));




