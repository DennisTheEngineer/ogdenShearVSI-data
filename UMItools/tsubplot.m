function handle = tsubplot(varargin)

switch nargin
    case {0,1,2};
        display('subplot needs at least three input arguments!');
        return
    case 3;
        gap=0;
    case 4;
        gap=varargin{4};
        if gap>0.1;           %gap was entered as a percentage
            gap=gap/100;
        end
    otherwise
        return
end
rows=varargin{1};
columns=varargin{2};
index=varargin{3};

%tsubplot is a tight subplot like axis generator 

ysize=1/rows;
xsize=1/columns;

xcoords=(0:columns-1)*xsize+xsize*gap;
ycoords=(rows-1:-1:0)*ysize+ysize*gap;

[Y X]=meshgrid(ycoords,xcoords);

handle=axes('Position',[X(index), Y(index), (1-2*gap)*xsize, (1-2*gap)*ysize]); 
end

