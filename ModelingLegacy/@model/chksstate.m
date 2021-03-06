function [flag, varargout] = chksstate(this, varargin)
% chksstate  Check if equations hold for currently assigned steady-state values.
%
%
% __Syntax__
%
%     [flag, list] = chksstate(model, ...)
%     [flag, discr, list] = chksstate(model, ...)
%
% __Input Arguments__
%
% * `model` [ model ] - Model object with steady-state values assigned.
%
%
% __Output Arguments__
%
% * `flag` [ `true` | `false` ] - True if discrepancy between LHS and RHS
% is smaller than tolerance level in each equation.
%
% * `discr` [ numeric ] - Discrepancies between LHS and RHS evaluated for
% each equation at two consecutive times, and returned as two column
% vectors.
%
% * `list` [ cellstr ] - List of equations in which the discrepancy between
% LHS and RHS is greater than predefined tolerance.
%
%
% __Options__
%
% * `Error=true` [ `true` | `false` ] - Throw an error if one or more
% equations fail to hold up to tolerance level.
%
% * `EquationSwitch='Dynamic'` [ `'Both'` | `'Dynamic'` | `'Steady'` ] - Check either
% dynamic equations or steady equations or both.
%
% * `Warning=true` [ `true` | `false` ] - Display warnings produced by this
% function.
%
%
% __Description__
%
%
% __Example__
%

% -IRIS Macroeconomic Modeling Toolbox
% -Copyright (c) 2007-2019 IRIS Solutions Team

TYPE = @int8;

persistent parser
if isempty(parser)
    parser = extend.InputParser('model.chksstate');
    parser.KeepUnmatched = true;
    parser.addRequired('Model', @(x) isa(x, 'model'));
    parser.addParameter('Error', true, @(x) isequal(x, true) || isequal(x, false));
    parser.addParameter('Warning', true, @(x) isequal(x, true) || isequal(x, false));
end
parse(parser, this, varargin{:});
opt = parser.Options;
needsSort = nargout>3;

% Pre-process options passed to checkSteady(~)
chksstateOpt = prepareCheckSteady(this, 'verbose', parser.UnmatchedInCell{:});

%--------------------------------------------------------------------------

% Refresh dynamic links.
if any(this.Link)
    this = refresh(this);
end

if opt.Warning
    if any(strcmpi(chksstateOpt.EquationSwitch, {'Dynamic', 'Full'}))
        chksstateOpt.EquationSwitch = 'Dynamic';
        chkQty(this, Inf, 'parameters:dynamic', 'sstate', 'log');
    else
        chksstateOpt.EquationSwitch = 'Steady';
        chkQty(this, Inf, 'parameters:steady', 'sstate', 'log');
    end
end

nv = length(this);

% `dcy` is a matrix of discrepancies; it has two columns when dynamic
% equations are evaluated, or one column when steady equations are
% evaluated.
[flag, dcy, maxAbsDiscr, list] = checkSteady(this, Inf, chksstateOpt);

if any(~flag) && opt.Error
    tmp = { };
    for i = find(~flag)
        for j = 1 : length(list{i})
            tmp{end+1} = exception.Base.alt2str(i); %#ok<AGROW>
            tmp{end+1} = list{i}{j}; %#ok<AGROW>
        end
    end
    if strcmpi(chksstateOpt.EquationSwitch, 'Dynamic')
        exc = exception.Base('Model:SteadyErrorInDynamic', 'error');
    else
        exc = exception.Base('Model:SteadyErrorInSteady', 'error');
    end
    throw(exc, tmp{:});
end

if needsSort
    sortList = cell(1, nv);
    for iAlt = 1 : nv
        [~, ix] = sort(maxAbsDiscr(:, iAlt), 1, 'descend');
        dcy(:, :, iAlt) = dcy(ix, :, iAlt);
        sortList{iAlt} = this.Equation.Input(ix);
    end
end

if nv==1
    list = list{1};
    if needsSort
        sortList = sortList{1};
    end
end

if nargout==2
    varargout{1} = list;
elseif nargout>2
    varargout{1} = dcy;
    varargout{2} = list;
    if needsSort
        varargout{3} = sortList;
    end
end

end%

