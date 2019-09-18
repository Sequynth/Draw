classdef DrawRGB < Draw
    
    properties (Access = private)
        t           % interrupt timer
        fps
        
        % DISPLAYING
        interruptedSlider
        locValString
        dimensionLabel
        inputNames
        valNames
        
        % UI Elements
        pImage
        pSlider
        pControls
        hBtnShiftL
        hBtnShiftR
        hBtnRotL
        hBtnRotR
        hBtnRun
        hEditF
        hTextFPS
        locAndVals
        hBtnSaveImg
        hBtnSaveVid
        
        hBtnG
        hRadioBtnSlider
        
        % UI properties
        
        pSliderHeight
        division
        margin 
        height
        yPadding
        panelPos
        figurePos
        
        isUint
    end
    
    properties (Constant, Access = private)
        % UI PROPERTIES
        % default figure position and size
        defaultPosition = [ 300, 200, 1000, 800];
        % absolute width of Control panel in pixel
        controlWidth = 275; % px
    end
    
    methods
        function obj = DrawRGB(in, varargin)
            % CONSTRUCTOR
            obj@Draw(in, varargin{:})
            
            % only one Axis in DrawSingle
            obj.nAxes    = 1;
            obj.activeAx = 1;
            obj.nSlider  = numel(obj.S) - 3;
            obj.mapSliderToImage = num2cell(ones(1, obj.nSlider));
            obj.standardTitle = inputname(1);
            obj.complexMode = 3;
            if isa(in, 'uint8')
                obj.isUint = true;
            else
                obj.isUint = false;
            end
            
            obj.prepareParser()
            
            % additional parameters
            addParameter(obj.p, 'Position',         obj.defaultPosition,                @(x) isnumeric(x) && numel(x) == 4);
            addParameter(obj.p, 'InitSlice',        round(obj.S(3:end)/2),              @isnumeric);
            addParameter(obj.p, 'FPS',              0,                                  @isnumeric);
            addParameter(obj.p, 'ROI_Signal',       [0 0; 0 0; 0 0],                    @isnumeric);
            addParameter(obj.p, 'ROI_Noise',        [0 0; 0 0; 0 0],                    @isnumeric);
            addParameter(obj.p, 'SaveImage',        '',                                 @ischar);
            addParameter(obj.p, 'SaveVideo',        '',                                 @ischar);
            addParameter(obj.p, 'LoopDimension',    3,                                  @(x) isnumeric(x) && x <= obj.nDims && obj.nDims >= 3);
            addParameter(obj.p, 'DimensionLabel',   strcat(repmat({'Dim'}, 1, numel(obj.S)), ...
                                                    cellfun(@num2str, num2cell(1:obj.nDims), 'UniformOutput', false)), ...
                                                                                        @(x) iscell(x) && numel(x) == obj.nSlider+2);
          
            parse(obj.p, varargin{:});
                        
            if contains('dimensionLabel', obj.p.UsingDefaults)
                for ff = 1:obj.nDims
                    obj.dimensionLabel{ff} = [obj.p.Results.DimensionLabel{ff} num2str(ff)];
                end
            else
                obj.dimensionLabel = obj.p.Results.DimensionLabel;
            end
                        
            obj.cmap{1}             = obj.p.Results.Colormap;
            obj.fps                 = obj.p.Results.FPS;
            obj.resize              = obj.p.Results.Resize;
                        
            obj.prepareColors()
            
            obj.createSelector()            
            
            obj.activeDim = 3;
            obj.interruptedSlider = 1;
            % necessary for view orientation, already needed when saving image or video
            obj.azimuthAng   = 0;
            obj.elevationAng = 90;
            
            % get name of input variable
            obj.inputNames{1} = inputname(1);
            
            % when an image or a video is saved, dont create the GUI and
            % terminate the class after finishing
            if ~contains('SaveImage', obj.p.UsingDefaults)
                obj.saveImage(obj.p.Results.SaveImage);
                clear obj
                return
            end            
            if ~contains('SaveVideo', obj.p.UsingDefaults)
                obj.saveVideo(obj.p.Results.SaveVideo);
                clear obj
                return
            end
            
            obj.setLocValFunction            
            
            obj.prepareGUI()
            
            obj.guiResize()
            set(obj.f, 'Visible', 'on');
            
            % do not assign to 'ans' when called without assigned variable
            if nargout == 0
                clear obj
            end
        end
        
        
        function delete(obj)
            try
                stop(obj.t);
                delete(obj.t);
            catch
            end
        end
        
        
        function prepareGUI(obj)
            
            % adjust figure properties
            
            set(obj.f, ...
                'name',                 obj.p.Results.Title, ...
                'Units',                'pixel', ...
                'Position',             obj.p.Results.Position, ...
                'Visible',              'on', ...
                'ResizeFcn',            @obj.guiResize, ...
                'CloseRequestFcn',      @obj.closeRqst, ...
                'WindowKeyPress',       @obj.keyPress, ...
                'WindowButtonMotionFcn',@obj.mouseMovement, ...
                'WindowButtonUpFcn',    @obj.stopDragFcn);
            
            if obj.nDims > 2
                set(obj.f, ...
                    'WindowScrollWheelFcn', @obj.scrollSlider);
            end
            
            % absolute height of slider panel
            obj.pSliderHeight = obj.nSlider*30;%px
            obj.setPanelPos()
            
            % create and place panels
            obj.pImage  = uipanel( ...
                'Units',            'pixels', ...
                'Position',         obj.panelPos(1, :), ...
                'BackgroundColor',  obj.COLOR_BG, ...
                'HighLightColor',   obj.COLOR_BG, ...
                'ShadowColor',      obj.COLOR_B);
            
            obj.pSlider = uipanel( ...
                'Units',            'pixels', ...
                'Position',         obj.panelPos(2, :), ...
                'BackgroundColor',  obj.COLOR_BG, ...
                'HighLightColor',   obj.COLOR_BG, ...
                'ShadowColor',      obj.COLOR_B);
            
            obj.pControls  = uipanel( ...
                'Units',            'pixels', ...
                'Position',         obj.panelPos(3, :), ...
                'BackgroundColor',  obj.COLOR_BG, ...
                'HighLightColor',   obj.COLOR_BG, ...
                'ShadowColor',      obj.COLOR_B);
            
            % place UIcontrol elements
            
            obj.margin   = 0.02 * obj.controlWidth;
            obj.height   = 0.05 * 660;
            obj.yPadding = 0.01 * 660;
            
            obj.hBtnShiftL = uicontrol( ...
                'Parent',               obj.pControls, ...
                'Style',                'pushbutton', ...
                'Units',                'pixel', ...
                'String',               '<-', ...
                'Callback',             { @obj.shiftDims}, ...
                'FontUnits',            'normalized', ...
                'FontSize',             0.45, ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F);
            
            obj.hBtnRotL = uicontrol( ...
                'Parent',               obj.pControls, ...
                'Style',                'pushbutton', ...
                'Units',                'pixel', ...
                'String',               'rotL', ...
                'Callback',             { @obj.rotateView}, ...
                'FontUnits',            'normalized', ...
                'FontSize',             0.45, ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F);
            
            obj.hBtnRotR = uicontrol( ...
                'Parent',               obj.pControls, ...
                'Style',                'pushbutton', ...
                'Units',                'pixel', ...
                'String',               'rotR', ...
                'Callback',             { @obj.rotateView}, ...
                'FontUnits',            'normalized', ...
                'FontSize',             0.45, ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F);
            
            obj.hBtnShiftR = uicontrol( ...
                'Parent',               obj.pControls, ...
                'Style',                'pushbutton', ...
                'Units',                'pixel', ...
                'String',               '->', ...
                'Callback',             { @obj.shiftDims}, ...
                'FontUnits',            'normalized', ...
                'FontSize',             0.45, ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F);
            
            obj.hBtnRun = uicontrol( ...
                'Parent',               obj.pControls, ...
                'Style',                'pushbutton', ...
                'Units',                'pixel', ...
                'String',               'Run', ...
                'Callback',             { @obj.toggleTimer}, ...
                'FontUnits',            'normalized', ...
                'FontSize',             0.45, ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F);
            
            obj.hEditF = uicontrol( ...
                'Parent',               obj.pControls, ...
                'Style',                'edit', ...
                'Units',                'pixel', ...
                'String',               sprintf('%.2f', obj.fps), ...
                'HorizontalAlignment',  'left', ...
                'FontUnits',            'normalized', ...
                'FontSize',             0.6, ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F, ...
                'Enable',               'Inactive', ...
                'FontName',             'FixedWidth', ...
                'ButtonDownFcn',        @obj.removeListener, ...
                'Callback',             @obj.setFPS);
            
            obj.hTextFPS = uicontrol( ...
                'Parent',               obj.pControls, ...
                'Style',                'text', ...
                'Units',                'pixel', ...
                'String',               sprintf('fps'), ...
                'HorizontalAlignment',  'left', ...
                'FontUnits',            'normalized', ...
                'FontSize',             0.6, ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F);
            
            obj.locAndVals = annotation(obj.pControls, 'textbox', ...
                'LineStyle',            'none', ...
                'Units',                'pixel', ...
                'Position',             [obj.margin ...
                                        obj.margin+obj.height+2*obj.yPadding ...
                                        obj.controlWidth-2*obj.margin ...
                                        3*obj.height], ...
                'String',               '', ...
                'HorizontalAlignment',  'left', ...
                'FontUnits',            'pixel', ...
                'FontSize',             16, ...
                'FontName',             'FixedWidth', ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'Interpreter',          'Tex');
            
            obj.hBtnSaveImg = uicontrol( ...
                'Parent',               obj.pControls, ...
                'Style',                'pushbutton', ...
                'Units',                'pixel', ...
                'Position',             [obj.margin ...
                                        obj.margin ...
                                        (obj.controlWidth-3*obj.margin)/2 ...
                                        obj.height], ...
                'String',               'Save Image', ...
                'Callback',             { @obj.saveImgBtn}, ...
                'FontUnits',            'normalized', ...
                'FontSize',             0.45, ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F);
            
            obj.hBtnSaveVid = uicontrol( ...
                'Parent',               obj.pControls, ...
                'Style',                'pushbutton', ...
                'Units',                'pixel', ...
                'Position',             [(obj.controlWidth+obj.margin)/2 ...
                                        obj.margin ...
                                        (obj.controlWidth-3*obj.margin)/2 ...
                                        obj.height], ...
                'String',               'Save Video', ...
                'Callback',             { @obj.saveVidBtn}, ...
                'FontUnits',            'normalized', ...
                'FontSize',             0.45, ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F);
            
            obj.t = timer(...
                'BusyMode',         'queue', ...
                'ExecutionMode',    'fixedRate', ...
                'Period',           1, ...
                'StartDelay',       0, ...
                'TimerFcn',         @(t, event) obj.interrupt, ...
                'TasksToExecute',   Inf);
            
            % create uibuttongroup
            obj.hBtnG = uibuttongroup( ...
                'Parent',               obj.pSlider, ...
                'Visible',              'Off', ...
                'BackgroundColor',      obj.COLOR_BG, ...
                'ForegroundColor',      obj.COLOR_F, ...
                'ShadowColor',          obj.COLOR_B, ...
                'HighLightColor',       obj.COLOR_BG, ...
                'SelectionChangedFcn',  @(bg, event) obj.BtnGselection(bg, event));
            
            % create and position the sliders
            sliderHeight    = 6/(8*obj.nSlider);
            for iSlider = 1:obj.nSlider
                
                sliderHeight0   = 1 - (iSlider-1)/obj.nSlider - 1/(8*obj.nSlider) - sliderHeight;
                SliderWidth     = 0.75;
                SliderWidth0    = 0.2;
                IndexWidth      = 0.1;
                IndexWidth0     = 0.1;
                TextWidth       = 0.1;
                TextWidth0      = 0;
                
                obj.hTextSlider(iSlider) = uicontrol( ...
                    'Parent',           obj.pSlider, ...
                    'Style',            'text', ...
                    'Units',            'normalized', ...
                    'Position',         [TextWidth0 ...
                                        sliderHeight0 ...
                                        TextWidth ...
                                        sliderHeight], ...
                    'FontUnits',        'normalized', ...
                    'FontSize',         0.8, ...
                    'BackgroundColor',  obj.COLOR_BG, ...
                    'ForegroundColor',  obj.COLOR_F);                
                
                obj.hSlider(iSlider) = uicontrol( ...
                    'Parent',           obj.pSlider, ...
                    'Style',            'slider', ...
                    'Units',            'normalized', ...
                    'Position',         [SliderWidth0 ...
                                        sliderHeight0 ...
                                        SliderWidth ...
                                        sliderHeight], ...
                    'Callback',         @(src, eventdata) obj.newSlice(src, eventdata), ...
                    'BackgroundColor',  obj.COLOR_BG, ...
                    'ForegroundColor',  obj.COLOR_BG);
                
                addlistener(obj.hSlider(iSlider), ...
                    'ContinuousValueChange', ...
                    @(src, eventdata) obj.newSlice(src, eventdata));
                
                obj.hEditSlider(iSlider) = uicontrol( ...
                    'Parent',           obj.pSlider, ...
                    'Style',            'edit', ...
                    'Units',            'normalized', ...
                    'Position',         [IndexWidth0 ...
                                        sliderHeight0 ...
                                        IndexWidth ...
                                        sliderHeight], ...
                    'FontUnits',        'normalized', ...
                    'FontSize',         0.8, ...
                    'Enable',           'Inactive', ...
                    'Value',            iSlider, ...
                    'ButtonDownFcn',    @obj.removeListener, ...
                    'BackgroundColor',  obj.COLOR_BG, ...
                    'ForegroundColor',  obj.COLOR_F);
                
                set(obj.hEditSlider(iSlider), 'Callback', @obj.setSlider);
                
                obj.hRadioBtnSlider(iSlider) = uicontrol(obj.hBtnG, ...
                    'Style',            'radiobutton', ...
                    'Units',            'normalized', ...
                    'Tag',              num2str(iSlider), ...
                    'Position',         [SliderWidth0+SliderWidth+0.02 ...
                                        sliderHeight0 ...
                                        0.02 ...
                                        sliderHeight], ...
                    'HandleVisibility', 'off', ...
                    'BackgroundColor',  obj.COLOR_BG, ...
                    'ForegroundColor',  obj.COLOR_F);
            end
            
            obj.initializeSliders
            
            obj.initializeAxis(true)
            
            if ~sum(ismember(obj.p.UsingDefaults, 'FPS')) && length(obj.S) > 2
                obj.fps = obj.p.Results.FPS;
                set(obj.hBtnRun, 'String', 'Stop')
                obj.setAndStartTimer
            end
            
        end
        
        
        function prepareSliceData(obj)
            % obtain image information form
            sel_temp = obj.sel;
            sel_temp{1, end} = ':';
            obj.slice{1, 1} = squeeze(obj.img{1}(sel_temp{1, :}));
        end
        
        
        function cImage = sliceMixer(obj)
            % calculates an RGB image depending on the windowing values,
            % the used colormaps and the current slice position. when the
            % slice position was changed, obj.prepareSliceData should be
            % run before calling the slice mixer.
            % axNo defines the axis for which the image is prepared.
            if obj.isUint
                cImage = double(obj.slice{1, 1})/255;
            else
                cImage = obj.slice{1, 1};
            end
        end
        
        
        function initializeAxis(obj, firstCall)
            % initializeAxis is called, to create the GUI, or when the
            % dimensions of the image are shifted and a reset of UI elements is
            % necessary. Both cases differ in the value of the bool 'firstCall'
            % This includes:
            %   axes        ax1
            %   ROIs
            %   imageData   h1
            
            if ~firstCall
                delete(ax1)
                deleteROIs()
            end
            
            obj.sel(1, ~obj.showDims) = num2cell(round(obj.S(~obj.showDims)/2));
             
            obj.prepareSliceData;

            ax      = axes('Parent', obj.pImage, 'Units', 'normal', 'Position', [0 0 1 1]);            
            obj.hImage  = imagesc(obj.sliceMixer(), 'Parent', ax);  % plot image

            hold on
            eval(['axis ', obj.p.Results.AspectRatio]);
            set(ax, ...
                'XTickLabel',   '', ...
                'YTickLabel',   '', ...
                'XTick',        [], ...
                'YTick',        []);
            set(obj.hImage, 'ButtonDownFcn', @obj.startDragFcn)
            colormap(ax, obj.cmap{1});
            
            view([obj.azimuthAng obj.elevationAng])
        end
        
        
        function initializeSliders(obj)
            % get the size, dimensionNo, and labels only for the sliders
            s = size(obj.img{1});
            labels = obj.dimensionLabel;
            s(     obj.showDims) = [];
            labels(obj.showDims) = [];
            
            for iSlider = 1:obj.nSlider
                set(obj.hTextSlider(iSlider), 'String', labels{iSlider});
                
                % if dimension is singleton, set slider steps to 0
                if s(iSlider) == 1
                    steps = [0 0];
                else
                    steps = [1/(s(iSlider)-1) 10/(s(iSlider)-1)];
                end
                                
                set(obj.hSlider(iSlider), ...
                    'Min',              1, ...
                    'Max',              s(iSlider), ...
                    'Value',            obj.sel{obj.dimMap(iSlider)}, ...
                    'SliderStep',       steps);
                if s(iSlider) == 1
                    set(obj.hSlider(iSlider), ...
                        'Enable',       'off');
                end
                
                set(obj.hEditSlider(iSlider), 'String', num2str(obj.sel{obj.dimMap(iSlider)}));
            end
        end
        
        
        function setPanelPos(obj)
            % create a 3x4 array that stores the 'Position' information for
            % the three panels pImage, pSlider, pControl
            
            obj.figurePos = get(obj.f, 'Position');
            
            if obj.figurePos(3) < obj.controlWidth
                set(gcf, ...
                    'Position', [obj.figurePos(1) ...
                                obj.figurePos(2) ...
                                obj.controlWidth ...
                                obj.figurePos(4)]);
            end
            
            % pImage
            obj.panelPos(1, :) =    [obj.controlWidth ...
                                    obj.pSliderHeight ...
                                    obj.figurePos(3) - obj.controlWidth ...
                                    obj.figurePos(4) - obj.pSliderHeight];
            % pSlider                    
            obj.panelPos(2, :) =    [obj.controlWidth ...
                                    0 ...
                                    obj.figurePos(3) - obj.controlWidth ...
                                    obj.pSliderHeight];
            % pControl                    
            obj.panelPos(3, :) =    [0 ...
                                    0 ...
                                    obj.controlWidth ...
                                    obj.figurePos(4)];
        end
        
        
        function createSelector(obj)
            % which dimensions are shown initially
            obj.showDims = [1 2];
            obj.dimMap   = 3:obj.nDims;
            % create slice selector for dimensions 3 and higher
            obj.sel        = repmat({':'}, 1, ndims(obj.img{1}));
            obj.sel(ismember(1:obj.nDims, obj.dimMap)) = num2cell(obj.p.Results.InitSlice);
        end
        
        
        function setLocValFunction(obj)
            if obj.nImages == 1
                obj.locValString = @(dim1L, dim1, dim2L, dim2, val) sprintf('\\color[rgb]{%.2f,%.2f,%.2f}%s:%4d\n%s:%4d\n%s:%s', ...
                    obj.COLOR_F, ...
                    dim1L, ...
                    dim1, ...
                    dim2L, ...
                    dim2, ...
                    obj.valNames{1}, ...
                    [num2sci(val) ' ' obj.p.Results.Unit{1}]);
            else
                obj.locValString = @(dim1L, dim1, dim2L, dim2, val1, val2) sprintf('\\color[rgb]{%.2f,%.2f,%.2f}%s:%4d\n%s:%4d\n\\color[rgb]{%.2f,%.2f,%.2f}%s:%s\n\\color[rgb]{%.2f,%.2f,%.2f}%s:%s', ...
                    obj.COLOR_F, ...
                    dim1L, ...
                    dim1, ...
                    dim2L, ...
                    dim2, ...
                    obj.COLOR_m(1, :), ...
                    obj.valNames{1}, ...
                    [num2sci(val1) obj.p.Results.Unit{1}], ...
                    obj.COLOR_m(2, :), ...
                    obj.valNames{2}, ...
                    [num2sci(val2) obj.p.Results.Unit{2}]);
            end
        end
        
        
        function locVal(obj, point)
            if ~isempty(point)
                % select all color values
                point{3} = ':';
                val = obj.slice{1, 1}(point{:});
                set(obj.locAndVals, 'String', ...
                    sprintf('\\color[rgb]{%.2f,%.2f,%.2f}%s:%4d\n%s:%4d\n\\color[rgb]{1,0.3,0.3}%s\n\\color[rgb]{0.3,1,0.3}%s\n\\color[rgb]{0.3,0.3,1}%s', ...
                    obj.COLOR_F, ...
                    obj.dimensionLabel{obj.showDims(1)}, ...
                    point{1}, ...
                    obj.dimensionLabel{obj.showDims(2)}, ...
                    point{2}, ...
                    num2sci(val(1)), num2sci(val(2)), num2sci(val(3))));
            else
                set(obj.locAndVals, 'String', '');
            end
        end
        
        
        function refreshUI(obj)            
            obj.prepareSliceData;            
            set(obj.hImage, 'CData', obj.sliceMixer());
            
            for iSlider = 1:obj.nSlider
                set(obj.hEditSlider(iSlider), 'String', num2str(obj.sel{obj.dimMap(iSlider)}));
                set(obj.hSlider(iSlider), 'Value', obj.sel{obj.dimMap(iSlider)});
            end
            % update 'val' when changing slice
            obj.mouseMovement();
        end
        
        
        function keyPress(obj, src, ~)
            % in case of 3D input, the image stack can be scrolled with 1 and 3
            % on the numpad
            key = get(src, 'CurrentCharacter');
            switch(key)
                case '1'
                    obj.incDecActiveDim(-1);
                case '3'
                    obj.incDecActiveDim(+1);
            end
        end
        
        
        function incDecActiveDim(obj, incDec)
            % change the active dimension by incDec
            obj.sel{1, obj.activeDim} = obj.sel{1, obj.activeDim} + incDec;
            % check whether the value is too large and take the modulus
            obj.sel{1, obj.activeDim} = mod(obj.sel{1, obj.activeDim}-1, obj.S(obj.activeDim))+1;
            obj.refreshUI();
        end
        
        
        function interrupt(obj, ~, ~)
            % this function is called for every interrupt of the timer and
            % increments/decrements the slider value.
            if obj.fps > 0
                obj.sel{1, obj.interruptedSlider+2} = obj.sel{1, obj.interruptedSlider+2} + 1;
            elseif obj.fps < 0
                obj.sel{1, obj.interruptedSlider+2} = obj.sel{1, obj.interruptedSlider+2} - 1;
            end
                obj.sel{1, obj.interruptedSlider+2} = mod(obj.sel{1, obj.interruptedSlider+2}-1, obj.S(obj.interruptedSlider+2))+1;
            obj.refreshUI();
        end
        
        
        function setFPS(obj, src, ~)
            % called by the center and width edit fields
            s = get(src, 'String');
            %turn "," into "."
            s(s == ',') = '.';
            
            obj.fps = str2double(s);
            % set(src, 'String', num2str(obj.fps));
            stop(obj.t)
            set(obj.hBtnRun, 'String', 'Run');
            if obj.fps ~= 0
                obj.setAndStartTimer;
                set(obj.hBtnRun, 'String', 'Stop');
            end
        end
        
        
        function setAndStartTimer(obj)
            %make sure fps is not higher 100
            obj.t.Period    = 1/abs(obj.fps) + (abs(obj.fps) > 100)*(1/100-1/abs(obj.fps));
            obj.t.TimerFcn  = @(t, event) obj.interrupt(obj.fps);
            set(obj.hEditF, 'String', num2str(sign(obj.fps)/obj.t.Period));
            start(obj.t)
        end
        
        
        function toggleTimer(obj, ~, ~)
            %called by the 'Run'/'Stop' button and controls the state of the
            %timer
            if strcmp(get(obj.t, 'Running'), 'off') && obj.fps ~= 0
                obj.setAndStartTimer;
                set(obj.hBtnRun, 'String',  'Stop');
                set(obj.hBtnG,   'Visible', 'on');
            else
                stop(obj.t)
                set(obj.hBtnRun, 'String',  'Run');
                set(obj.hBtnG,   'Visible', 'off');
            end
        end
        
        
        function saveImgBtn(obj, ~, ~)
            % get the filepath from a UI and call saveImage funciton to save
            % the image
            [filename, filepath] = uiputfile({'*.jpg; *.png'}, 'Save image', '.png');
            if filepath == 0
                % uipufile was closed without providing filename.
                return
            else
                obj.saveImage([filepath, filename])
            end
        end
        
        
        function saveImage(obj, path)
            % save image of current slice with current windowing to filename
            % definde in path
            
            obj.prepareSliceData;       
            % apply the current azimuthal rotation to the image and save
            imwrite(rot90(obj.sliceMixer(), -obj.azimuthAng/90), path);
        end
        
        
        function saveVidBtn(obj, ~, ~)
            % get the filepath from a UI and call saveVideo funciton to save
            % the video or gif
            [filename, filepath] = uiputfile({'*.avi', 'AVI-file (*.avi)'; ...
                '*.gif', 'gif-Animation (*.gif)'}, ...
                'Save video', '.avi');
            if filepath == 0
                return
            else
                obj.saveVideo([filepath, filename])
            end
        end
        
        
        function saveVideo(obj, path)
            % save video of matrix with current windowing and each frame being
            % one slice in the 3rd dimension.
            
            % get the state of the timer
            bRunning = strcmp(obj.t.Running, 'on');
            % stop the interrupt, to get control over the data shown.
            if bRunning
                stop(obj.t)
            end
            
            if strcmp(path(end-2:end), 'avi') || strcmp(path(end-2:end), 'gif')
                
                if  strcmp(path(end-2:end), 'gif')
                    gif = 1;
                else
                    gif = 0;
                    % start the video writer
                    v           = VideoWriter(path);
                    v.FrameRate = obj.fps;
                    v.Quality   = 100;
                    open(v);
                end
                % select the looping slices that are currently shown in the DrawSingle
                % window, resize image, apply the colormap and rotate according
                % to the azimuthal angle of the view.
                for ii = 1: obj.S(obj.interruptedSlider+2)
                    obj.sel{obj.interruptedSlider+2} = ii;
                    obj.prepareSliceData
                    imgOut = rot90(obj.sliceMixer(), -obj.azimuthAng/90);
                    
                    if gif
                        [gifImg, cm] = rgb2ind(imgOut, 256);
                        if ii == 1
                            imwrite(gifImg, cm, path, 'gif', ...
                                'WriteMode',    'overwrite', ...
                                'DelayTime',    1/obj.fps, ...
                                'LoopCount',    Inf);
                        else
                            imwrite(gifImg, cm, path, 'gif', ...
                                'WriteMode',    'append',...
                                'DelayTime',    1/obj.fps);
                        end
                    else
                        writeVideo(v, imgOut);
                    end
                end
            else
                warning('Invalid filename! Data was not saved.');
            end
            
            if ~gif
                close(v)
            end
            % restart the timer if it was running before
            if bRunning
                start(obj.t)
            end
        end
        
        
        function closeRqst(obj, varargin)
            % closeRqst is called, when the user closes the figure (by 'x' or
            % 'close'). It stops and deletes the timer, frees up memory taken
            % by img and closes the figure.
%             try
%                 stop(obj.t);
%                 delete(obj.t);
%             catch
%             end
%             delete(obj.f);
            delete(obj.f);
            obj.delete
        end
        
        
        function rotateView(obj, src, ~)
            % function is called by the two buttons (rotL, rotR)
            switch (src.String)
                case 'rotL'
                    obj.azimuthAng = mod(obj.azimuthAng - 90, 360);
                case 'rotR'
                    obj.azimuthAng = mod(obj.azimuthAng + 90, 360);
            end
            view([obj.azimuthAng obj.elevationAng])
        end
        
        
        function shiftDims(obj, src, ~)
            disp('Functionality not yet implemented')
        end
        
        
        function guiResize(obj, varargin)
            obj.setPanelPos()
            
            set(obj.pImage,     'Position', obj.panelPos(1, :));
            set(obj.pSlider,    'Position', obj.panelPos(2, :));
            set(obj.pControls,  'Position', obj.panelPos(3, :));
             
            
            n = 5;
            position = obj.positionN(n, 4);
            set(obj.hBtnShiftL, 'Position', position(1, :));
            set(obj.hBtnRotL,   'Position', position(2, :));
            set(obj.hBtnRotR,   'Position', position(3, :));
            set(obj.hBtnShiftR, 'Position', position(4, :));
            
            n = n + 1;
            position = obj.positionN(n, 3);
            set(obj.hBtnRun,    'Position', position(1, :))
            set(obj.hEditF,     'Position', position(2, :))
            set(obj.hTextFPS,   'Position', position(3, :))
            
        end
            
        
        function pos = divPosition(obj, N)
            yPos = ceil(obj.figurePos(4)-obj.margin-N*obj.height-(N-1)*obj.yPadding);
            if obj.nImages == 1
                pos = [obj.margin ...
                    yPos ...
                    obj.division-2*obj.margin ...
                    obj.height; ...
                    obj.division+obj.margin/2 ...
                    yPos ...
                    (obj.controlWidth-obj.division)-obj.margin ...
                    obj.height];
            else
                pos = [obj.margin ...
                    yPos ...
                    obj.division-2*obj.margin ...
                    obj.height; ...
                    obj.division+obj.margin/2 ...
                    yPos ...
                    (obj.controlWidth-obj.division)/2-5/4*obj.margin ...
                    obj.height; ...
                    obj.division+obj.margin/2+((obj.controlWidth-obj.division)/2-3/4*obj.margin) ...
                    yPos ...
                    (obj.controlWidth-obj.division)/2-5/4*obj.margin ...
                    obj.height];
            end
        end
        
        
        function pos = divPosition3(obj, N)
            yPos = ceil(obj.figurePos(4)-obj.margin-N*obj.height-(N-1)*obj.yPadding);
            pos = [obj.division+obj.margin/2 ...
                yPos ...
                (obj.controlWidth-obj.division-7/2*obj.margin)/3 ...
                obj.height; ...
                obj.division+1/2*obj.margin+(obj.controlWidth-obj.division-1/2*obj.margin)/3 ...
                yPos ...
                (obj.controlWidth-obj.division-7/2*obj.margin)/3 ...
                obj.height; ...
                obj.division+1/2*obj.margin+2*(obj.controlWidth-obj.division-1/2*obj.margin)/3 ...
                yPos ...
                (obj.controlWidth-obj.division-7/2*obj.margin)/3 ...
                obj.height];
        end
        
        
        function pos = positionN(obj, h, n)
            % h: heigth value
            % n: number of equally spaced horitonzal elements
            yPos  = ceil(obj.figurePos(4)-obj.margin-h*obj.height-(h-1)*obj.yPadding);
            width =(obj.controlWidth-(n+1)*obj.margin)/n;
            
            pos   = repmat([0 yPos width obj.height], [n, 1]);
            xPos  = (0:(n-1)) * (width+ obj.margin) + obj.margin;
            
            pos(:, 1) = xPos;
        end
    end
end