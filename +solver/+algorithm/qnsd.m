function [x, numericExitFlag] = qnsd(objectiveFunc, xInit, opt)
% qnsd  Quasi-Newton-Steepest-Descent algorithm
%
% Backend IRIS function
% No help provided

% -IRIS Macroeconomic Modeling Toolbox
% -Copyright (c) 2007-2018 IRIS Solutions Team

FORMAT_HEADER = '%6s %8s %13s %6s %13s %13s %13s %13s';
FORMAT_ITER   = '%6g %8g %13g %6g %13g %13g %13g %13g';
MIN_STEP = 1e-8;
MAX_STEP = 2;

%--------------------------------------------------------------------------

vecLmb = opt.Lambda;
if isempty(vecLmb)
    strStepType = 'Newton';
else
    strStepType = 'Hybrid';
end
if isa(opt.FunctionNorm, 'function_handle')
    fnNorm = opt.FunctionNorm;
    strFnNorm = func2str(fnNorm);
    strFnNorm = regexprep(strFnNorm, '^@\(.*?\)', '', 'once');
    if length(strFnNorm)>12
        strFnNorm = strFnNorm(1:12);
    end
else
    fnNorm = @(x) norm(x, opt.FunctionNorm);
    strFnNorm = sprintf('norm(x,%g)', opt.FunctionNorm);
end
if opt.SpecifyObjectiveGradient
    strJacobNorm = 'Analytical';
else
    strJacobNorm = 'Numerical';
end
stepDown = opt.StepDown;
stepUp = opt.StepUp;
isStepDown = ~isequal(stepDown, false);
isStepUp = ~isequal(stepUp, false);
diffStep = opt.FiniteDifferenceStepSize;
if ~opt.SpecifyObjectiveGradient
    jacobPattern = opt.JacobPattern;
end

sizeOfX = size(xInit);
if any(sizeOfX(2:end)>1)
    objectiveFuncReshaped = @(x) objectiveFunc(reshape(x, sizeOfX));
else
    objectiveFuncReshaped = @(x) objectiveFunc(x);
end

xInit = xInit(:);
numUnknowns = numel(xInit);

temp = struct( ...
    'NumberOfVariables', numUnknowns ...
);

displayLevel = getDisplayLevel( );
tolX = opt.StepTolerance;
tolFun = opt.FunctionTolerance;
maxIter = opt.MaxIterations;
maxFunEvals = opt.MaxFunctionEvaluations;
if isa(maxIter, 'function_handle')
    maxIter = maxIter(temp);
end
if isa(maxFunEvals, 'function_handle')
    maxFunEvals = maxFunEvals(temp);
end

x = xInit;
lmb = NaN;
step = NaN;
n0 = NaN;
iter = 0;
fnCount = 0;
x0 = xInit;
j = NaN;
j0 = NaN;

if displayLevel.Iter
    displayHeader( );
end

w = warning( );
warning('off', 'MATLAB:nearlySingularMatrix');

while true
    if opt.SpecifyObjectiveGradient
        [fx, j] = objectiveFuncReshaped(x);
        fx = fx(:);
        fnCount = fnCount + 1;
    else
        fx = objectiveFuncReshaped(x);
        fx = fx(:);
        fnCount = fnCount + 1;
        [j, addCount] = solver.algorithm.finiteDifference( objectiveFuncReshaped, ...
                                                           x, fx, diffStep, ...
                                                           jacobPattern, opt.LargeScale );
        fnCount = fnCount + addCount;
    end
    n = fnNorm(fx);
    
    if hasConverged( ) 
        % Convergence reached, exit.
        exitFlag = solver.ExitFlag.CONVERGED;
        break
    end
    
    if iter>maxIter
        % Max iter reached, exit.
        exitFlag = solver.ExitFlag.MAX_ITER;
        break
    end
    
    if fnCount>maxFunEvals
        % Max fun evals reached, exit.
        exitFlag = solver.ExitFlag.MAX_FUN_EVALS;
        break
    end
   
    if displayLevel.Iter
        displayIter( );
        fprintf('\n');
    end
    x0 = x;
    % f0 = f;
    n0 = n;
    j0 = j;

    step = 1;
    if isempty(vecLmb)
        [d, n] = makeNewtonStep( );
    else
        [d, n] = makeHybridStep( );
    end

    q = 0;
    if n>n0 && isStepDown
        % Shrink step until objective function improves.
        makeStepDown( );
    elseif isStepUp
        % Inflate step as far as objective function improves.
        makeStepUp( );
    end
    
    if n>n0
        % No further progress can be made, exit.
        exitFlag = solver.ExitFlag.NO_PROGRESS;
        break
    end

    x = x + step*d;
    iter = iter + 1;
end

warning(w);

if displayLevel.Iter
    isDesktop = getappdata(0, 'IRIS_IsDesktop');
    if isDesktop
        fprintf('<strong>');
    end
    displayIter( );
    if isDesktop
        fprintf('</strong>');
    end
    fprintf('\n');
end

if displayLevel.Final
    displayFinal( );
end

if displayLevel.Any
    fprintf('\n');
end

numericExitFlag = double(exitFlag);

return


    function [d, n] = makeNewtonStep( )
        lmb = 0;
        d = -j \ fx;
        c = x + step*d;
        fx = objectiveFuncReshaped(c);
        fx = fx(:);
        fnCount = fnCount + 1;
        n = fnNorm(fx);
    end%


    function [d, n] = makeHybridStep( )
        jj = j.'*j;
        if issparse(j)
            maxSv = svds(j, 1, 'largest');
            minSv = svds(j, 1, 'smallest');
        else
            sj = svd(j);
            maxSv = max(sj);
            minSv = sj(end);
        end
        tol = numUnknowns * eps(maxSv);
        vecOfLambdas0 = vecLmb;
        if minSv>tol
            vecOfLambdas0 = [0, vecOfLambdas0];
        end
        nlmb0 = numel(vecOfLambdas0);
        scale = tol * eye(numUnknowns);
        
        % Optimize lambda
        dd = cell(1, nlmb0);
        nn = nan(1, nlmb0);
        ff = cell(1, nlmb0);
        for i = 1 : nlmb0
            if vecOfLambdas0(i)==0
                % Lambda=0; run Newton step
                dd{i} = -j \ fx;
            else
                % Lambda>0; run hybrid step
                dd{i} = -( jj + vecOfLambdas0(i)*scale ) \ j.' * fx;
            end
            c = x + step*dd{i};
            ff{i} = objectiveFuncReshaped(c);
            fnCount = fnCount + 1;
            nn(i) = fnNorm(ff{i});
        end
        [~, pos] = min(nn);
        lmb = vecOfLambdas0(pos);
        d = dd{pos};
        fx = ff{pos};
        n = nn(pos);
    end%


    function makeStepDown( )
        % Shrink step until objective function improves.
        while n>n0 && step>MIN_STEP
            step = stepDown*step;
            c = x + step*d;
            fx = objectiveFuncReshaped(c);
            fx = fx(:);
            fnCount = fnCount + 1;
            q = q + 1;
            n = fnNorm(fx);
        end
    end


    function makeStepUp( )
        % Inflate step as far as objective function improves.
        while step<MAX_STEP
            c = x + stepUp*step*d;
            fx = objectiveFuncReshaped(c);
            fx = fx(:);
            fnCount = fnCount + 1;
            q = q + 1;
            n1 = fnNorm(fx);
            if n1>=n || q>=40
                break
            end
            n = n1;
            step = stepUp*step;
        end
    end        


    function flag = hasConverged( )
        flag = all( maxabs(fx)<=tolFun );
        if iter>0
            flag = flag && all( maxabs(x-x0)<=tolX );
        end
    end


    function displayHeader( )
        fprintf('\n');
        c1 = sprintf( ...
            FORMAT_HEADER, ...
            'Iter', ...
            'Fn-Count', ...
            'Fn-Norm', ...
            'Lambda', ...
            'Step-Size', ...
            'Fn-Norm-Chg', ...
            'Max-X-Chg', ...
            'Max-Jacob-Chg' ...
        );
        c2 = sprintf( ...
            FORMAT_HEADER, ...
            '', ...
            '', ...
            strFnNorm, ...
            strStepType, ...
            '', ...
            '', ...
            '', ...
            strJacobNorm ...
        );
        disp(c1);
        disp(c2);
        disp( repmat('-', 1, max(length(c1), length(c2))) );
    end%


    function displayIter( )
        maxChgX = max(abs(x(:)-x0(:)));
        maxChgJ = full(max(abs(j(:)-j0(:))));
        fprintf( ...
            FORMAT_ITER, ...
            iter, ...
            fnCount, ...
            n, ...
            lmb, ...
            step, ...
            n-n0, ...
            maxChgX, ...
            maxChgJ ...
        );
    end%


    function displayFinal( )
        print(exitFlag);
    end%


    function displayLevel = getDisplayLevel( )
        displayLevel.Any = ...
            ~isequal(opt.Display, false) ...
            && ~strcmpi(opt.Display, 'none') ...
            && ~strcmpi(opt.Display, 'off');
        displayLevel.Final = displayLevel.Any;
        displayLevel.Iter = ...
            isequal(opt.Display, true) ...
            || strcmpi(opt.Display, 'iter') ...
            || strcmpi(opt.Display, 'iter*');
    end%
end%
