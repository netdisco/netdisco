/**
 * This is the global function which encapsulates all variables and methods. All
 * parameters are optional.
 *
 * The shortest possible way to get up and running a graph with the shipped sample data:
 *
 *     example = netGobrechtsD3Force().start();
 *
 * You can then interact with the graph API like so:
 *
 *     example.width(800).height(600).resume();
 * @see {@link module:API.start}
 * @see {@link module:API.render}
 * @see {@link module:API.resume}
 * @param {string} [domContainerId] - The DOM container, where the graph should be rendered
 * @param {Object} [options] - The configuration object to configure the graph
 * @param {string} [apexPluginId] - APEX plugin only: The plugin identifier for the AJAX calls
 * @param  {string} [apexPageItemsToSubmit] - APEX plugin only: Page items to submit before an AJAX call
 * @returns {Object} The public graph API function to allow method chaining
 */
function netGobrechtsD3Force(domContainerId, options, apexPluginId, apexPageItemsToSubmit) { // jshint ignore:line
    /* exported netGobrechtsD3Force */
    /* globals apex, $v, navigator, d3, document, console, window, clearInterval, ActiveXObject, DOMParser, setTimeout */
    /* jshint -W101 */

    "use strict";

    // setup graph variable
    var v = {
        "conf": {},
        "confDefaults": {},
        "data": {},
        "dom": {},
        "events": {},
        "lib": {},
        "main": {},
        "status": {},
        "tools": {},
        "version": "x.x.x"
    };

    /**
     * A module representing the public graph API.
     * @exports API
     */
    var graph = {};

    /**
     * A helper function to initialize the graph
     */
    v.main.init = function() {

        // save parameter for later use
        v.dom.containerId = domContainerId || "D3Force" + Math.floor(Math.random() * 1000000);
        v.confUser = options || {};
        v.status.apexPluginId = apexPluginId;
        v.status.apexPageItemsToSubmit = (!apexPageItemsToSubmit || apexPageItemsToSubmit === "" ? false :
            apexPageItemsToSubmit.replace(/\s/g, "").split(","));

        // initialize the graph function
        v.main.setupConfiguration();
        v.main.setupDom();
        v.main.setupFunctionReferences();
    };


    /*******************************************************************************************************************
     * MAIN: SETUP CONFIGURATION
     */
    v.main.setupConfiguration = function() {
        /* jshint -W074, -W071 */
        // configure debug mode for APEX, can be overwritten by users configuration object
        // or later on with the API debug method
        v.conf.debug = (v.status.apexPluginId && apex.jQuery("#pdebug").length === 1);
        v.status.debugPrefix = "D3 Force in DOM container #" + v.dom.containerId + ": ";

        // status variables
        v.status.customize = false;
        v.status.customizeCurrentMenu = "nodes";
        v.status.customizeCurrentTabPosition = null;
        v.status.forceTickCounter = 0;
        v.status.forceStartTime = 0;
        v.status.forceRunning = false;
        v.status.graphStarted = false;
        v.status.graphRendering = false;
        v.status.graphReady = false;
        v.status.graphOldPositions = null;
        v.status.sampleData = false;
        v.status.wrapLabelsOnNextTick = false;
        v.status.labelFontSize = null;

        // default configuration
        v.confDefaults.minNodeRadius = {
            "display": true,
            "relation": "node",
            "type": "number",
            "val": 6,
            "options": [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
        };
        v.confDefaults.maxNodeRadius = {
            "display": true,
            "relation": "node",
            "type": "number",
            "val": 18,
            "options": [36, 34, 32, 30, 28, 26, 24, 22, 20, 18, 16, 14, 12]
        };
        v.confDefaults.colorScheme = {
            "display": true,
            "relation": "node",
            "type": "text",
            "val": "color20",
            "options": ["color20", "color20b", "color20c", "color10", "direct"]
        };
        v.confDefaults.dragMode = {
            "display": true,
            "relation": "node",
            "type": "bool",
            "val": true,
            "options": [true, false]
        };
        v.confDefaults.pinMode = {
            "display": true,
            "relation": "node",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.nodeEventToStopPinMode = {
            "display": true,
            "relation": "node",
            "type": "text",
            "val": "contextmenu",
            "options": ["none", "dblclick", "contextmenu"]
        };
        v.confDefaults.onNodeContextmenuPreventDefault = {
            "display": true,
            "relation": "node",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.nodeEventToOpenLink = {
            "display": true,
            "relation": "node",
            "type": "text",
            "val": "dblclick",
            "options": ["none", "click", "dblclick", "contextmenu"]
        };
        v.confDefaults.nodeLinkTarget = {
            "display": true,
            "relation": "node",
            "type": "text",
            "val": "_blank",
            "options": ["none", "_blank", "nodeID", "domContainerID"]
        };
        v.confDefaults.showLabels = {
            "display": true,
            "relation": "label",
            "type": "bool",
            "val": true,
            "options": [true, false]
        };
        v.confDefaults.wrapLabels = {
            "display": true,
            "relation": "label",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.wrappedLabelWidth = {
            "display": true,
            "relation": "label",
            "type": "number",
            "val": 80,
            "options": [200, 190, 180, 170, 160, 150, 140, 130, 120, 110, 100, 90, 80, 70, 60, 50, 40]
        };
        v.confDefaults.wrappedLabelLineHeight = {
            "display": true,
            "relation": "label",
            "type": "number",
            "val": 1.2,
            "options": [1.5, 1.4, 1.3, 1.2, 1.1, 1.0]
        };
        v.confDefaults.labelsCircular = {
            "display": true,
            "relation": "label",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.labelDistance = {
            "display": true,
            "relation": "label",
            "type": "number",
            "val": 12,
            "options": [30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8, 6, 4, 2]
        };
        v.confDefaults.preventLabelOverlappingOnForceEnd = {
            "display": true,
            "relation": "label",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.labelPlacementIterations = {
            "display": true,
            "relation": "label",
            "type": "number",
            "val": 250,
            "options": [2000, 1000, 500, 250, 125]
        };
        v.confDefaults.showTooltips = {
            "display": true,
            "relation": "node",
            "type": "bool",
            "val": true,
            "options": [true, false]
        };
        v.confDefaults.tooltipPosition = {
            "display": true,
            "relation": "node",
            "type": "text",
            "val": "svgTopRight",
            "options": ["node", "svgTopLeft", "svgTopRight"]
        };
        v.confDefaults.alignFixedNodesToGrid = {
            "display": true,
            "relation": "node",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.gridSize = {
            "display": true,
            "relation": "node",
            "type": "number",
            "val": 50,
            "options": [150, 140, 130, 120, 110, 100, 90, 80, 70, 60, 50, 40, 30, 20, 10]
        };

        v.confDefaults.linkDistance = {
            "display": true,
            "relation": "link",
            "type": "number",
            "val": 80,
            "options": [120, 110, 100, 90, 80, 70, 60, 50, 40, 30, 20]
        };
        v.confDefaults.showLinkDirection = {
            "display": true,
            "relation": "link",
            "type": "bool",
            "val": true,
            "options": [true, false]
        };
        v.confDefaults.showSelfLinks = {
            "display": true,
            "relation": "link",
            "type": "bool",
            "val": true,
            "options": [true, false]
        };
        v.confDefaults.selfLinkDistance = {
            "display": true,
            "relation": "link",
            "type": "number",
            "val": 20,
            "options": [30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10, 8]
        };

        v.confDefaults.useDomParentWidth = {
            "display": true,
            "relation": "graph",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.width = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": 500,
            "options": [1200, 1150, 1100, 1050, 1000, 950, 900, 850, 800, 750, 700, 650, 600, 550, 500, 450, 400, 350,
                300
            ]
        };
        v.confDefaults.height = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": 500,
            "options": [1200, 1150, 1100, 1050, 1000, 950, 900, 850, 800, 750, 700, 650, 600, 550, 500, 450, 400, 350,
                300
            ]
        };
        v.confDefaults.setDomParentPaddingToZero = {
            "display": true,
            "relation": "graph",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.showBorder = {
            "display": true,
            "relation": "graph",
            "type": "bool",
            "val": true,
            "options": [true, false]
        };
        v.confDefaults.showLegend = {
            "display": true,
            "relation": "graph",
            "type": "bool",
            "val": true,
            "options": [true, false]
        };
        v.confDefaults.showLoadingIndicatorOnAjaxCall = {
            "display": true,
            "relation": "graph",
            "type": "bool",
            "val": true,
            "options": [true, false]
        };
        v.confDefaults.lassoMode = {
            "display": true,
            "relation": "graph",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.zoomMode = {
            "display": true,
            "relation": "graph",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.minZoomFactor = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": 0.2,
            "options": [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1]
        };
        v.confDefaults.maxZoomFactor = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": 5,
            "options": [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
        };
        v.confDefaults.transform = {
            "display": false,
            "relation": "graph",
            "type": "object",
            "val": {
                "translate": [0, 0],
                "scale": 1
            }
        };
        v.confDefaults.zoomToFitOnForceEnd = {
            "display": true,
            "relation": "graph",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.autoRefresh = {
            "display": true,
            "relation": "graph",
            "type": "bool",
            "val": false,
            "options": [true, false]
        };
        v.confDefaults.refreshInterval = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": 5000,
            "options": [60000, 30000, 15000, 10000, 5000, 2500]
        };
        v.confDefaults.chargeDistance = {
            "display": false,
            "relation": "graph",
            "type": "number",
            "val": Infinity,
            "options": [Infinity, 25600, 12800, 6400, 3200, 1600, 800, 400, 200, 100],
            "internal": true
        };
        v.confDefaults.charge = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": -350,
            "options": [-1000, -950, -900, -850, -800, -750, -700, -650, -600, -550, -500, -450, -400, -350, -300, -250, -200, -150, -100, -50, 0], // jshint ignore:line
            "internal": true
        };
        v.confDefaults.gravity = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": 0.1,
            "options": [1.00, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40, 0.35, 0.30, 0.25,
                0.20, 0.15, 0.1, 0.05, 0.00
            ],
            "internal": true
        };
        v.confDefaults.linkStrength = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": 1,
            "options": [1.00, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40, 0.35, 0.30, 0.25,
                0.20, 0.15, 0.10, 0.05, 0.00
            ],
            "internal": true
        };
        v.confDefaults.friction = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": 0.9,
            "options": [1.00, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40, 0.35, 0.30, 0.25,
                0.20, 0.15, 0.10, 0.05, 0.00
            ],
            "internal": true
        };
        v.confDefaults.theta = {
            "display": true,
            "relation": "graph",
            "type": "number",
            "val": 0.8,
            "options": [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6, 0.55, 0.5, 0.45, 0.4, 0.35, 0.3, 0.25, 0.2, 0.15,
                0.1, 0.05, 0
            ],
            "internal": true
        };

        // create intial configuration
        v.conf.debug = (typeof v.confUser.debug !== "undefined" ? v.tools.parseBool(v.confUser.debug) : false);

        v.conf.minNodeRadius = v.confUser.minNodeRadius || v.confDefaults.minNodeRadius.val;
        v.conf.maxNodeRadius = v.confUser.maxNodeRadius || v.confDefaults.maxNodeRadius.val;
        v.conf.colorScheme = v.confUser.colorScheme || v.confDefaults.colorScheme.val;
        v.conf.dragMode = (typeof v.confUser.dragMode !== "undefined" ? v.tools.parseBool(v.confUser.dragMode) :
            v.confDefaults.dragMode.val);
        v.conf.pinMode = (typeof v.confUser.pinMode !== "undefined" ? v.tools.parseBool(v.confUser.pinMode) :
            v.confDefaults.pinMode.val);
        v.conf.nodeEventToStopPinMode = v.confUser.nodeEventToStopPinMode || v.confDefaults.nodeEventToStopPinMode.val;
        v.conf.onNodeContextmenuPreventDefault = (typeof v.confUser.onNodeContextmenuPreventDefault !== "undefined" ?
            v.tools.parseBool(v.confUser.onNodeContextmenuPreventDefault) :
            v.confDefaults.onNodeContextmenuPreventDefault.val);
        v.conf.nodeEventToOpenLink = v.confUser.nodeEventToOpenLink || v.confDefaults.nodeEventToOpenLink.val;
        v.conf.nodeLinkTarget = v.confUser.nodeLinkTarget || v.confDefaults.nodeLinkTarget.val;
        v.conf.showLabels = (typeof v.confUser.showLabels !== "undefined" ? v.tools.parseBool(v.confUser.showLabels) :
            v.confDefaults.showLabels.val);
        v.conf.wrapLabels = (typeof v.confUser.wrapLabels !== "undefined" ? v.tools.parseBool(v.confUser.wrapLabels) :
            v.confDefaults.wrapLabels.val);
        v.conf.wrappedLabelWidth = v.confUser.wrappedLabelWidth || v.confDefaults.wrappedLabelWidth.val;
        v.conf.wrappedLabelLineHeight = v.confUser.wrappedLabelLineHeight || v.confDefaults.wrappedLabelLineHeight.val;
        v.conf.labelsCircular = (typeof v.confUser.labelsCircular !== "undefined" ?
            v.tools.parseBool(v.confUser.labelsCircular) : v.confDefaults.labelsCircular.val);
        v.conf.labelDistance = v.confUser.labelDistance || v.confDefaults.labelDistance.val;
        v.conf.preventLabelOverlappingOnForceEnd =
            (typeof v.confUser.preventLabelOverlappingOnForceEnd !== "undefined" ?
                v.tools.parseBool(v.confUser.preventLabelOverlappingOnForceEnd) :
                v.confDefaults.preventLabelOverlappingOnForceEnd.val);
        v.conf.labelPlacementIterations = v.confUser.labelPlacementIterations ||
            v.confDefaults.labelPlacementIterations.val;
        v.conf.showTooltips = (typeof v.confUser.showTooltips !== "undefined" ?
            v.tools.parseBool(v.confUser.showTooltips) : v.confDefaults.showTooltips.val);
        v.conf.tooltipPosition = v.confUser.tooltipPosition || v.confDefaults.tooltipPosition.val;
        v.conf.alignFixedNodesToGrid = (typeof v.confUser.alignFixedNodesToGrid !== "undefined" ?
            v.tools.parseBool(v.confUser.alignFixedNodesToGrid) : v.confDefaults.alignFixedNodesToGrid.val);
        v.conf.gridSize = (v.confUser.gridSize && v.confUser.gridSize > 0 ?
            v.confUser.gridSize : v.confDefaults.gridSize.val);

        v.conf.linkDistance = v.confUser.linkDistance || v.confDefaults.linkDistance.val;
        v.conf.showLinkDirection = (typeof v.confUser.showLinkDirection !== "undefined" ?
            v.tools.parseBool(v.confUser.showLinkDirection) : v.confDefaults.showLinkDirection.val);
        v.conf.showSelfLinks = (typeof v.confUser.showSelfLinks !== "undefined" ?
            v.tools.parseBool(v.confUser.showSelfLinks) : v.confDefaults.showSelfLinks.val);
        v.conf.selfLinkDistance = v.confUser.selfLinkDistance || v.confDefaults.selfLinkDistance.val;

        v.conf.useDomParentWidth = (typeof v.confUser.useDomParentWidth !== "undefined" ?
            v.tools.parseBool(v.confUser.useDomParentWidth) : v.confDefaults.useDomParentWidth.val);
        v.conf.width = v.confUser.width || v.confDefaults.width.val;
        v.conf.height = v.confUser.height || v.confDefaults.height.val;
        v.conf.setDomParentPaddingToZero = (typeof v.confUser.setDomParentPaddingToZero !== "undefined" ?
            v.tools.parseBool(v.confUser.setDomParentPaddingToZero) : v.confDefaults.setDomParentPaddingToZero.val);
        v.conf.showBorder = (typeof v.confUser.showBorder !== "undefined" ? v.tools.parseBool(v.confUser.showBorder) :
            v.confDefaults.showBorder.val);
        v.conf.showLegend = (typeof v.confUser.showLegend !== "undefined" ? v.tools.parseBool(v.confUser.showLegend) :
            v.confDefaults.showLegend.val);
        v.conf.showLoadingIndicatorOnAjaxCall = (typeof v.confUser.showLoadingIndicatorOnAjaxCall !== "undefined" ?
            v.tools.parseBool(v.confUser.showLoadingIndicatorOnAjaxCall) :
            v.confDefaults.showLoadingIndicatorOnAjaxCall.val);
        v.conf.lassoMode = (typeof v.confUser.lassoMode !== "undefined" ? v.tools.parseBool(v.confUser.lassoMode) :
            v.confDefaults.lassoMode.val);
        v.conf.zoomMode = (typeof v.confUser.zoomMode !== "undefined" ? v.tools.parseBool(v.confUser.zoomMode) :
            v.confDefaults.zoomMode.val);
        v.conf.minZoomFactor = v.confUser.minZoomFactor || v.confDefaults.minZoomFactor.val;
        v.conf.maxZoomFactor = v.confUser.maxZoomFactor || v.confDefaults.maxZoomFactor.val;
        v.conf.transform = v.confUser.transform || v.confDefaults.transform.val;
        v.conf.zoomToFitOnForceEnd = (typeof v.confUser.zoomToFitOnForceEnd !== "undefined" ? v.tools.parseBool(v.confUser.zoomToFitOnForceEnd) :
            v.confDefaults.zoomToFitOnForceEnd.val);
        v.conf.autoRefresh = (typeof v.confUser.autoRefresh !== "undefined" ?
            v.tools.parseBool(v.confUser.autoRefresh) : v.confDefaults.autoRefresh.val);
        v.conf.refreshInterval = v.confUser.refreshInterval || v.confDefaults.refreshInterval.val;
        v.conf.chargeDistance = v.confUser.chargeDistance || Infinity;
        v.conf.charge = v.confUser.charge || v.confDefaults.charge.val;
        v.conf.gravity = v.confUser.gravity || v.confDefaults.gravity.val;
        v.conf.linkStrength = v.confUser.linkStrength || v.confDefaults.linkStrength.val;
        v.conf.friction = v.confUser.friction || v.confDefaults.friction.val;
        v.conf.theta = v.confUser.theta || v.confDefaults.theta.val;

        v.conf.onNodeMouseenterFunction = v.confUser.onNodeMouseenterFunction || null;
        v.conf.onNodeMouseleaveFunction = v.confUser.onNodeMouseleaveFunction || null;
        v.conf.onNodeClickFunction = v.confUser.onNodeClickFunction || null;
        v.conf.onNodeDblclickFunction = v.confUser.onNodeDblclickFunction || null;
        v.conf.onNodeContextmenuFunction = v.confUser.onNodeContextmenuFunction || null;
        v.conf.onLinkClickFunction = v.confUser.onLinkClickFunction || null;
        v.conf.onLassoStartFunction = v.confUser.onLassoStartFunction || null;
        v.conf.onLassoEndFunction = v.confUser.onLassoEndFunction || null;

        // initialize sample data
        /* jshint -W110 */
        v.data.sampleData = '<data>' +
            '<nodes ID="7839" LABEL="KING is THE KING, you know?" LABELCIRCULAR="true" COLORVALUE="10" ' +
            'COLORLABEL="Accounting" SIZEVALUE="5000" LINK="http://apex.oracle.com/" ' +
            'INFOSTRING="This visualization is based on the well known emp table." />' +
            '<nodes ID="7698" LABEL="BLAKE" COLORVALUE="30" COLORLABEL="Sales" SIZEVALUE="2850" />' +
            '<nodes ID="7782" LABEL="CLARK" COLORVALUE="10" COLORLABEL="Accounting" SIZEVALUE="2450" />' +
            '<nodes ID="7566" LABEL="JONES" COLORVALUE="20" COLORLABEL="Research" SIZEVALUE="2975" />' +
            '<nodes ID="7788" LABEL="SCOTT with a very long label" ' +
            'COLORVALUE="20" COLORLABEL="Research" SIZEVALUE="3000" />' +
            '<nodes ID="7902" LABEL="FORD" COLORVALUE="20" COLORLABEL="Research" SIZEVALUE="3000" />' +
            '<nodes ID="7369" LABEL="SMITH" COLORVALUE="20" COLORLABEL="Research" SIZEVALUE="800" />' +
            '<nodes ID="7499" LABEL="ALLEN" COLORVALUE="30" COLORLABEL="Sales" SIZEVALUE="1600" />' +
            '<nodes ID="7521" LABEL="WARD" COLORVALUE="30" COLORLABEL="Sales" SIZEVALUE="1250" />' +
            '<nodes ID="7654" LABEL="MARTIN" COLORVALUE="30" COLORLABEL="Sales" SIZEVALUE="1250" />' +
            '<nodes ID="7844" LABEL="TURNER" COLORVALUE="30" COLORLABEL="Sales" SIZEVALUE="1500" />' +
            '<nodes ID="7876" LABEL="ADAMS" COLORVALUE="20" COLORLABEL="Research" SIZEVALUE="1100" />' +
            '<nodes ID="7900" LABEL="JAMES" COLORVALUE="30" COLORLABEL="Sales" SIZEVALUE="950" />' +
            '<nodes ID="7934" LABEL="MILLER" COLORVALUE="10" COLORLABEL="Accounting" SIZEVALUE="1300" />' +
            '<nodes ID="8888" LABEL="Who am I?" COLORVALUE="green" COLORLABEL="unspecified" SIZEVALUE="2000" ' +
            'LINK="https://github.com/ogobrecht/d3-force-apex-plugin/wiki/API-Reference#nodelinktarget" ' +
            'INFOSTRING="This is a good question. Think about it." />' +
            '<nodes ID="9999" LABEL="Where I am?" COLORVALUE="#f00" COLORLABEL="unspecified" SIZEVALUE="1000" ' +
            'LINK="https://github.com/ogobrecht/d3-force-apex-plugin/wiki/API-Reference#nodelinktarget" ' +
            'INFOSTRING="This is a good question. What do you think?" />' +
            '<links FROMID="7839" TOID="7839" STYLE="dotted" COLOR="blue" ' +
            'INFOSTRING="This is a self link (same source and target node) rendered along a path with the STYLE ' +
            'attribute set to dotted and COLOR attribute set to blue." />' +
            '<links FROMID="7698" TOID="7839" STYLE="dashed" />' +
            '<links FROMID="7782" TOID="7839" STYLE="dashed" COLOR="red" INFOSTRING="This is a link with the STYLE ' +
            'attribute set to dashed and COLOR attribute set to red." />' +
            '<links FROMID="7566" TOID="7839" STYLE="dashed" />' +
            '<links FROMID="7788" TOID="7566" STYLE="solid" />' +
            '<links FROMID="7902" TOID="7566" STYLE="solid" />' +
            '<links FROMID="7369" TOID="7902" STYLE="solid" />' +
            '<links FROMID="7499" TOID="7698" STYLE="solid" />' +
            '<links FROMID="7521" TOID="7698" STYLE="solid" />' +
            '<links FROMID="7654" TOID="7698" STYLE="solid" />' +
            '<links FROMID="7844" TOID="7698" STYLE="solid" />' +
            '<links FROMID="7876" TOID="7788" STYLE="solid" />' +
            '<links FROMID="7900" TOID="7698" STYLE="solid" />' +
            '<links FROMID="7934" TOID="7782" STYLE="solid" />' +
            '</data>';
        /* jshint +W110 */

        // check user agent: http://stackoverflow.com/questions/16135814/check-for-ie-10
        v.status.userAgent = navigator.userAgent;
        v.status.userAgentIe9To11 = false;
        // Hello IE 9 - 11
        if (navigator.appVersion.indexOf("MSIE 9") !== -1 ||
            navigator.appVersion.indexOf("MSIE 10") !== -1 ||
            v.status.userAgent.indexOf("Trident") !== -1 && v.status.userAgent.indexOf("rv:11") !== -1) {
            v.status.userAgentIe9To11 = true;
            v.tools.logError("Houston, we have a problem - user agent is IE 9, 10 or 11 - we have to provide a fix " +
                "for markers: " +
                "http://stackoverflow.com/questions/15588478/internet-explorer-10-not-showing-svg-path-d3-js-graph");
        }

    }; // --> END v.main.setupConfiguration

    /*******************************************************************************************************************
     * MAIN: SETUP DOM
     */
    v.main.setupDom = function() {

        // create reference to body
        v.dom.body = d3.select("body");

        // create DOM container element, if not existing (if we have an APEX context, it is already created from the
        // APEX engine )
        if (document.querySelector("#" + v.dom.containerId) === null) {
            v.dom.container = v.dom.body.append("div")
                .attr("id", v.dom.containerId);
        } else {
            v.dom.container = d3.select("#" + v.dom.containerId);
            d3.selectAll("#" + v.dom.containerId + "_customizing").remove();
            // d3.selectAll("#" + v.dom.containerId + "_tooltip").remove();
        }

        // create SVG element, if not existing (if we have an APEX context, it is already created from the APEX plugin )
        if (document.querySelector("#" + v.dom.containerId + " svg") === null) {
            v.dom.svg = v.dom.container.append("svg");
        } else {
            v.dom.svg = d3.select("#" + v.dom.containerId + " svg");
            d3.selectAll("#" + v.dom.containerId + " svg *").remove();
        }

        v.dom.svgParent = d3.select(v.dom.svg.node().parentNode);
        if (v.conf.setDomParentPaddingToZero) {
            v.dom.svgParent.style("padding", "0");
        }

        // configure SVG element
        v.dom.svg
            .attr("class", "net_gobrechts_d3_force")
            .classed("border", v.conf.showBorder)
            .attr("width", v.conf.width)
            .attr("height", v.conf.height);

        // calculate width of SVG parent
        v.dom.containerWidth = v.tools.getSvgParentInnerWidth();
        if (v.conf.useDomParentWidth) {
            v.dom.svg.attr("width", v.dom.containerWidth);
        }

        // create definitions element inside the SVG element
        v.dom.defs = v.dom.svg.append("defs");

        // create overlay element to fetch events for lasso & zoom
        v.dom.graphOverlay = v.dom.svg.append("g").attr("class", "graphOverlay");

        // create element for resizing the overlay g element
        v.dom.graphOverlaySizeHelper = v.dom.graphOverlay.append("rect").attr("class", "graphOverlaySizeHelper");

        // create graph group element for zoom and pan
        v.dom.graph = v.dom.graphOverlay.append("g").attr("class", "graph");

        // create legend group element
        v.dom.legend = v.dom.svg.append("g").attr("class", "legend");

        // create loading indicator
        v.dom.loading = v.dom.svg.append("svg:g")
            .attr("class", "loading")
            .style("display", "none");
        v.dom.loadingRect = v.dom.loading
            .append("svg:rect")
            .attr("width", v.tools.getGraphWidth())
            .attr("height", v.conf.height);
        v.dom.loadingText = v.dom.loading
            .append("svg:text")
            .attr("x", v.tools.getGraphWidth() / 2)
            .attr("y", v.conf.height / 2)
            .text("Loading...");

        // create marker definitions
        v.dom.defs
            .append("svg:marker")
            .attr("id", v.dom.containerId + "_highlighted")
            .attr("class", "highlighted")
            .attr("viewBox", "0 0 10 10")
            .attr("refX", 10)
            .attr("refY", 5)
            .attr("markerWidth", 5)
            .attr("markerHeight", 5)
            .attr("orient", "auto")
            .attr("markerUnits", "strokeWidth")
            .append("svg:path")
            .attr("d", "M0,0 L10,5 L0,10");

        v.dom.defs
            .append("svg:marker")
            .attr("id", v.dom.containerId + "_normal")
            .attr("class", "normal")
            .attr("viewBox", "0 0 10 10")
            .attr("refX", 10)
            .attr("refY", 5)
            .attr("markerWidth", 5)
            .attr("markerHeight", 5)
            .attr("orient", "auto")
            .attr("markerUnits", "strokeWidth")
            .append("svg:path")
            .attr("d", "M0,0 L10,5 L0,10");

        // create tooltip container
        if (document.querySelector("#" + v.dom.containerId + "_tooltip") === null) {
            v.dom.tooltip = v.dom.body.append("div")
                .attr("id", v.dom.containerId + "_tooltip")
                .attr("class", "net_gobrechts_d3_force_tooltip")
                .style("top", "0px")
                .style("left", "0px");
        } else {
            v.dom.tooltip = d3.select("#" + v.dom.containerId + "_tooltip");
        }

    }; // --> END v.main.setupDom


    /*******************************************************************************************************************
     * MAIN: SETUP FUNCTION REFERENCES
     */
    v.main.setupFunctionReferences = function() {

        // create force reference
        v.main.force = d3.layout.force()
            .on("start", function() {
                v.tools.log("Force started.");
                if (v.status.customize && v.dom.customizePositions) {
                    v.dom.customizePositions.text("Force started - wait for end event to show positions...");
                }
                v.status.forceTickCounter = 0;
                v.status.forceStartTime = new Date().getTime();
                v.status.forceRunning = true;
            })
            .on("tick", function() {
                v.status.forceTickCounter += 1;
                // hello IE 9 - 11:
                // http://stackoverflow.com/questions/15588478/internet-explorer-10-not-showing-svg-path-d3-js-graph
                if (v.status.userAgentIe9To11 && v.conf.showLinkDirection) {
                    v.main.links.each(function() {
                        this.parentNode.insertBefore(this, this);
                    });
                    v.main.selfLinks.each(function() {
                        this.parentNode.insertBefore(this, this);
                    });
                }
                v.main.selfLinks
                    .attr("transform", function(l) {
                        return "translate(" + l.source.x + "," + l.source.y + ")";
                    });
                v.main.links
                    .attr("x1", function(l) {
                        return v.tools.adjustSourceX(l);
                    })
                    .attr("y1", function(l) {
                        return v.tools.adjustSourceY(l);
                    })
                    .attr("x2", function(l) {
                        return v.tools.adjustTargetX(l);
                    })
                    .attr("y2", function(l) {
                        return v.tools.adjustTargetY(l);
                    });
                if (v.conf.showLabels) {
                    v.main.labels
                        .attr("x", function(l) {
                            return l.x;
                        })
                        .attr("y", function(l) {
                            return l.y - l.radius - v.conf.labelDistance;
                        });

                    if (v.status.wrapLabelsOnNextTick) {
                        v.main.labels.call(v.tools.wrapLabels, v.conf.wrappedLabelWidth);
                        v.status.wrapLabelsOnNextTick = false;
                    }
                    // reposition on every tick only
                    if (v.conf.wrapLabels) {
                        v.main.labels.each(function() {
                            var label = d3.select(this);
                            var y = label.attr("y") - (label.attr("lines") - 1) *
                                v.status.labelFontSize * v.conf.wrappedLabelLineHeight;
                            label.attr("y", y)
                                .selectAll("tspan")
                                .attr("x", label.attr("x"))
                                .attr("y", y);
                        });
                    }
                    v.main.labelPaths
                        .attr("transform", function(n) {
                            return "translate(" + n.x + "," + n.y + ")";
                        });
                }
                v.main.nodes
                    .attr("cx", function(n) {
                        return n.x;
                    })
                    .attr("cy", function(n) {
                        return n.y;
                    });

            })
            .on("end", function() {
                if (v.conf.showLabels && v.conf.preventLabelOverlappingOnForceEnd) {
                    v.data.simulatedAnnealingLabels = [];
                    v.data.simulatedAnnealingAnchors = [];
                    v.main.labels.each(function(node, i) {
                        var label = d3.select(this);
                        v.data.simulatedAnnealingLabels[i] = {
                            width: this.getBBox().width,
                            height: this.getBBox().height,
                            x: node.x,
                            y: label.attr("y") - (label.attr("lines") - 1) *
                                v.status.labelFontSize * v.conf.wrappedLabelLineHeight
                        };
                    });
                    v.main.nodes.filter(function(n) {
                        return !n.LABELCIRCULAR && !v.conf.labelsCircular;
                    }).each(function(node, i) {
                        v.data.simulatedAnnealingAnchors[i] = {
                            x: node.x,
                            // set anchors to the same positions as the label
                            y: node.y - node.radius - v.conf.labelDistance,
                            //fake radius for labeler plugin, because our labels are already outside of the nodes
                            r: 0.5

                        };
                    });
                    v.lib.labelerPlugin()
                        .label(v.data.simulatedAnnealingLabels)
                        .anchor(v.data.simulatedAnnealingAnchors)
                        .width(v.tools.getGraphWidth())
                        .height(v.conf.height)
                        .start(v.conf.labelPlacementIterations);
                    v.main.labels.each(function(node, i) {
                        var label = d3.select(this),
                            x = v.data.simulatedAnnealingLabels[i].x,
                            y = v.data.simulatedAnnealingLabels[i].y;
                        if (v.conf.wrapLabels) {
                            y = y - (label.attr("lines") - 1) * v.status.labelFontSize * v.conf.wrappedLabelLineHeight;
                            label
                                .transition()
                                .duration(800)
                                .attr("x", x)
                                .attr("y", y)
                                .selectAll("tspan")
                                .attr("x", x)
                                .attr("y", y);
                        } else {
                            label
                                .transition()
                                .duration(800)
                                .attr("x", x)
                                .attr("y", y);
                        }
                    });
                }
                if (v.conf.zoomToFitOnForceEnd && v.conf.zoomMode) {
                    graph.zoomToFit();
                }
                v.status.forceRunning = false;
                var milliseconds = new Date().getTime() - v.status.forceStartTime;
                var seconds = (milliseconds / 1000).toFixed(1);
                var ticksPerSecond = Math.round(v.status.forceTickCounter / (milliseconds / 1000));
                var millisecondsPerTick = Math.round(milliseconds / v.status.forceTickCounter);
                if (v.status.customize && v.dom.customizePositions) {
                    v.dom.customizePositions.text(JSON.stringify(graph.positions()));
                }
                v.tools.log("Force ended.");
                v.tools.log(seconds + " seconds, " + v.status.forceTickCounter + " ticks to cool down (" +
                    ticksPerSecond + " ticks/s, " + millisecondsPerTick + " ms/tick).");
            });

        // create drag reference
        v.main.drag = v.main.force.drag();

        // create lasso reference
        v.main.lasso = v.lib.lassoPlugin()
            .closePathDistance(100) // max distance for the lasso loop to be closed
            .closePathSelect(true) // can items be selected by closing the path?
            .hoverSelect(true) // can items by selected by hovering over them?
            .area(v.dom.graphOverlay) // area where the lasso can be started
            .pathContainer(v.dom.svg); // Container for the path

        // create zoom reference
        v.main.zoom = d3.behavior.zoom();

        // create zoomed function
        v.main.zoomed = function() {
            v.conf.transform = {
                "translate": v.main.zoom.translate(),
                "scale": v.main.zoom.scale()
            };
            v.dom.graph.attr("transform", "translate(" + v.main.zoom.translate() + ")scale(" +
                v.main.zoom.scale() + ")");
            v.tools.writeConfObjectIntoWizard();
        };

        // create interpolate zoom helper
        v.main.interpolateZoom = function(translate, scale, duration) {
            if (v.conf.zoomMode && v.status.graphStarted) {
                if (scale < v.conf.minZoomFactor) {
                    scale = v.conf.minZoomFactor;
                } else if (scale > v.conf.maxZoomFactor) {
                    scale = v.conf.maxZoomFactor;
                }
                return d3.transition().duration(duration).tween("zoom", function() {
                    var iTranslate = d3.interpolate(v.main.zoom.translate(), translate),
                        iScale = d3.interpolate(v.main.zoom.scale(), scale);
                    return function(t) {
                        v.main.zoom
                            .scale(iScale(t))
                            .translate(iTranslate(t));
                        v.main.zoomed();
                    };
                });
            }
        };

    }; // --> END v.main.setupFunctionReferences


    /*******************************************************************************************************************
     * HELPER FUNCTIONS
     */

    // helper to check boolean values
    v.tools.parseBool = function(value) {
        switch (String(value).trim().toLowerCase()) {
            case "true":
            case "yes":
            case "1":
                return true;
            case "false":
            case "no":
            case "0":
            case "":
                return false;
            default:
                return false;
        }
    };

    // parse XML string to XML
    v.tools.parseXml = function(xml) {
        var dom = null;
        if (xml) {
            if (window.DOMParser) {
                try {
                    dom = (new DOMParser()).parseFromString(xml, "text/xml");
                } catch (e) {
                    dom = null;
                    v.tools.logError("DOMParser - unable to parse XML: " + e.message);
                }
            } else if (window.ActiveXObject) {
                try {
                    dom = new ActiveXObject("Microsoft.XMLDOM");
                    dom.async = false;
                    // parse error ...
                    if (!dom.loadXML(xml)) {
                        v.tools.logError("Microsoft.XMLDOM - unable to parse XML: " + dom.parseError.reason +
                            dom.parseError.srcText);
                    }
                } catch (e) {
                    dom = null;
                    v.tools.logError("Microsoft.XMLDOM - unable to parse XML: " + e.message);
                }
            }
        }
        return dom;
    };

    // convert XML to JSON: modified version of http://davidwalsh.name/convert-xml-json
    v.tools.xmlToJson = function(xml) {
        var obj = null,
            subobj, item, subItem, nodeName, attribute;
        var convertItemToJson = function(item) {
            subobj = {};
            if (item.attributes.length > 0) {
                for (var i = 0; i < item.attributes.length; i++) {
                    attribute = item.attributes.item(i);
                    subobj[attribute.nodeName] = attribute.nodeValue;
                }
            }
            if (item.hasChildNodes()) {
                for (var j = 0; j < item.childNodes.length; j++) {
                    subItem = item.childNodes.item(j);
                    // check, if subItem has minimum one child (hopefully a textnode) inside
                    if (subItem.hasChildNodes()) {
                        subobj[subItem.nodeName] = subItem.childNodes.item(0).nodeValue;
                    } else {
                        subobj[subItem.nodeName] = "";
                    }
                }
            }
            return subobj;
        };
        if (xml) {
            obj = {};
            obj.data = {};
            obj.data.nodes = [];
            obj.data.links = [];
            if (xml.childNodes.item(0).hasChildNodes()) {
                for (var i = 0; i < xml.childNodes.item(0).childNodes.length; i++) {
                    subobj = null;
                    item = xml.childNodes.item(0).childNodes.item(i);
                    nodeName = item.nodeName;
                    if (nodeName === "nodes" || nodeName === "node") {
                        obj.data.nodes.push(convertItemToJson(item));
                    } else if (nodeName === "links" || nodeName === "link") {
                        obj.data.links.push(convertItemToJson(item));
                    }
                }
            }
        }
        return obj;
    };

    // get inner width for the SVG parents element
    v.tools.getSvgParentInnerWidth = function() {
        return parseInt(v.dom.svgParent.style("width")) -
            parseInt(v.dom.svgParent.style("padding-left")) -
            parseInt(v.dom.svgParent.style("padding-right")) -
            (v.dom.svg.style("border-width") ? parseInt(v.dom.svg.style("border-width")) : 1) * 2;
    };

    // helper function to get effective graph width
    v.tools.getGraphWidth = function() {
        return (v.conf.useDomParentWidth ? v.dom.containerWidth : v.conf.width);
    };

    // log function for debug mode
    v.tools.log = function(message, omitDebugPrefix) {
        if (v.conf.debug) {
            if (omitDebugPrefix) {
                console.log(message);
            } else {
                console.log(v.status.debugPrefix + message);
            }
        }
        if (v.status.customize && v.dom.customizeLog) {
            v.dom.customizeLog.text(message + "\n" + v.dom.customizeLog.text());
        }
    };

    // log error function
    v.tools.logError = function(message) {
        console.log(v.status.debugPrefix + "ERROR: " + message);
        if (v.status.customize && v.dom.customizeLog) {
            v.dom.customizeLog.text("ERROR: " + message + "\n" + v.dom.customizeLog.text());
        }
    };

    // trigger APEX events, if we have an APEX context
    v.tools.triggerApexEvent = function(domNode, event, data) {
        if (v.status.apexPluginId) {
            apex.event.trigger(domNode, event, data);
        }
    };

    // helper function to calculate node radius from "SIZEVALUE" attribute
    v.tools.setRadiusFunction = function() {
        v.tools.radius = d3.scale.sqrt()
            .range([v.conf.minNodeRadius, v.conf.maxNodeRadius])
            .domain(d3.extent(v.data.nodes, function(n) {
                return parseFloat(n.SIZEVALUE);
            }));
    };

    // helper function to calculate node fill color from COLORVALUE attribute
    v.tools.setColorFunction = function() {
        if (v.conf.colorScheme === "color20") {
            v.tools.color = d3.scale.category20();
        } else if (v.conf.colorScheme === "color20b") {
            v.tools.color = d3.scale.category20b();
        } else if (v.conf.colorScheme === "color20c") {
            v.tools.color = d3.scale.category20c();
        } else if (v.conf.colorScheme === "color10") {
            v.tools.color = d3.scale.category10();
        } else if (v.conf.colorScheme === "direct") {
            v.tools.color = function(d) {
                return d;
            };
        } else {
            v.conf.colorScheme = "color20";
            v.tools.color = d3.scale.category20();
        }
    };

    // check, if two nodes are neighbors
    v.tools.neighboring = function(a, b) {
        return (v.data.neighbors.indexOf(a.ID + ":" + b.ID) > -1 ||
            v.data.neighbors.indexOf(b.ID + ":" + a.ID) > -1);
    };

    // get nearest grid position
    v.tools.getNearestGridPosition = function(currentPos, maxPos) {
        var offset, position;
        // no size limit for calculated positions, if zoomMode is set to true
        if (v.conf.zoomMode) {
            offset = currentPos % v.conf.gridSize;
            position = (offset > v.conf.gridSize / 2 ? currentPos - offset + v.conf.gridSize : currentPos - offset);
        }
        // size limit for calculated positions is SVG size, if zoomMode is set to false
        else {
            if (currentPos >= maxPos) {
                offset = maxPos % v.conf.gridSize;
                position = maxPos - offset;
                if (position === maxPos) {
                    position = position - v.conf.gridSize;
                }
            } else if (currentPos <= v.conf.gridSize / 2) {
                position = v.conf.gridSize;
            } else {
                offset = currentPos % v.conf.gridSize;
                position = (offset > v.conf.gridSize / 2 ? currentPos - offset + v.conf.gridSize : currentPos - offset);
                if (position >= maxPos) {
                    position = position - v.conf.gridSize;
                }
            }
        }
        return position;
    };

    // adjust link x/y
    v.tools.adjustSourceX = function(l) {
        return l.source.x + Math.cos(v.tools.calcAngle(l)) * (l.source.radius);
    };
    v.tools.adjustSourceY = function(l) {
        return l.source.y + Math.sin(v.tools.calcAngle(l)) * (l.source.radius);
    };
    v.tools.adjustTargetX = function(l) {
        return l.target.x - Math.cos(v.tools.calcAngle(l)) * (l.target.radius);
    };
    v.tools.adjustTargetY = function(l) {
        return l.target.y - Math.sin(v.tools.calcAngle(l)) * (l.target.radius);
    };
    v.tools.calcAngle = function(l) {
        return Math.atan2(l.target.y - l.source.y, l.target.x - l.source.x);
    };

    // create a path for self links
    v.tools.getSelfLinkPath = function(l) {
        var ri = l.source.radius;
        var ro = l.source.radius + v.conf.selfLinkDistance;
        var x = 0; // we position the path later with transform/translate
        var y = 0;
        var pathStart = {
            "source": {
                "x": 0,
                "y": 0,
                "radius": ri
            },
            "target": {
                "x": (x + ro / 2),
                "y": (y + ro),
                "radius": ri
            }
        };
        var pathEnd = {
            "source": {
                "x": (x - ro / 2),
                "y": (y + ro),
                "radius": ri
            },
            "target": {
                "x": x,
                "y": y,
                "radius": ri
            }
        };
        var path = "M" + v.tools.adjustSourceX(pathStart) + "," + v.tools.adjustSourceY(pathStart);
        path += " L" + (x + ro / 2) + "," + (y + ro);
        path += " A" + ro + "," + ro + " 0 0,1 " + (x - ro / 2) + "," + (y + ro);
        path += " L" + v.tools.adjustTargetX(pathEnd) + "," + v.tools.adjustTargetY(pathEnd);
        return path;
    };

    // create a path for labels - example: d="M100,100 a20,20 0 0,1 40,0"
    v.tools.getLabelPath = function(n) {
        var r = n.radius + v.conf.labelDistance;
        var x = 0; // we position the path later with transform/translate
        var y = 0;
        var path = "M" + (x - r) + "," + y;
        //path += " a" + r + "," + r + " 0 0,1 " + (r * 2) + ",0";
        path += " a" + r + "," + r + " 0 0,1 " + (r * 2) + ",0";
        path += " a" + r + "," + r + " 0 0,1 -" + (r * 2) + ",0";
        return path;
    };

    // open link function
    v.tools.openLink = function(node) {
        var win;
        if (v.conf.nodeLinkTarget === "none") {
            window.location.assign(node.LINK);
        } else if (v.conf.nodeLinkTarget === "nodeID") {
            win = window.open(node.LINK, node.ID);
            win.focus();
        } else if (v.conf.nodeLinkTarget === "domContainerID") {
            win = window.open(node.LINK, v.dom.containerId);
            win.focus();
        } else {
            win = window.open(node.LINK, v.conf.nodeLinkTarget);
            win.focus();
        }
    };

    v.tools.applyConfigurationObject = function(confObject) {
        var key;
        for (key in confObject) {
            if (confObject.hasOwnProperty(key) &&
                v.conf.hasOwnProperty(key) &&
                confObject[key] !== v.conf[key]) {
                graph[key](confObject[key]);
            }
        }
    };

    // http://stackoverflow.com/questions/13713528/how-to-disable-pan-for-d3-behavior-zoom
    // http://stackoverflow.com/questions/11786023/how-to-disable-double-click-zoom-for-d3-behavior-zoom
    // zoom event proxy
    v.tools.zoomEventProxy = function(fn) {
        return function() {
            if (
                (!v.conf.dragMode || v.conf.dragMode && d3.event.target.tagName !== "circle") &&
                v.conf.zoomMode &&
                (!d3.event.altKey && !d3.event.shiftKey)
            ) {
                fn.apply(this, arguments);
            }
        };
    };
    // lasso event proxy
    v.tools.lassoEventProxy = function(fn) {
        return function() {
            if (
                (!v.conf.dragMode || d3.event.target.tagName !== "circle") &&
                v.conf.lassoMode &&
                (!v.conf.zoomMode || d3.event.altKey || d3.event.shiftKey)
            ) {
                fn.apply(this, arguments);
            }
        };
    };

    // show tooltip
    v.tools.showTooltip = function(text) {
        var position;
        v.dom.tooltip.html(text).style("display", "block");
        if (v.conf.tooltipPosition === "svgTopLeft") {
            position = v.tools.getOffsetRect(v.dom.svg.node());
            v.dom.tooltip
                .style("top", position.top +
                    (v.dom.svg.style("border-width") ? parseInt(v.dom.svg.style("border-width")) : 1) +
                    "px")
                .style("left", position.left +
                    (v.dom.svg.style("border-width") ? parseInt(v.dom.svg.style("border-width")) : 1) +
                    "px");
        } else if (v.conf.tooltipPosition === "svgTopRight") {
            position = v.tools.getOffsetRect(v.dom.svg.node());
            v.dom.tooltip
                .style("top", position.top +
                    parseInt((v.dom.svg.style("border-width") ? parseInt(v.dom.svg.style("border-width")) : 1)) +
                    "px")
                .style("left", position.left +
                    parseInt(v.dom.svg.style("width")) +
                    parseInt((v.dom.svg.style("border-width") ? parseInt(v.dom.svg.style("border-width")) : 1)) -
                    parseInt(v.dom.tooltip.style("width")) -
                    2 * parseInt(
                        (v.dom.tooltip.style("border-width") ? parseInt(v.dom.tooltip.style("border-width")) : 0)
                    ) -
                    parseInt(v.dom.tooltip.style("padding-left")) -
                    parseInt(v.dom.tooltip.style("padding-right")) +
                    "px");
        } else {
            v.dom.tooltip
                .style("left", d3.event.pageX + 10 + "px")
                .style("top", d3.event.pageY + "px");
        }
    };

    // hide tooltip
    v.tools.hideTooltip = function() {
        v.dom.tooltip.style("display", "none");
    };

    // on link click function
    v.tools.onLinkClick = function(link) {
        if (d3.event.defaultPrevented) { // ignore drag
            return null;
        } else {
            v.tools.log("Event link_click triggered.");
            v.tools.triggerApexEvent(this, "net_gobrechts_d3_force_linkclick", link);
            if (typeof(v.conf.onLinkClickFunction) === "function") {
                v.conf.onLinkClickFunction.call(this, d3.event, link);
            }
        }
    };
    // get marker URL
    v.tools.getMarkerUrl = function(l) {
        if (v.conf.showLinkDirection) {
            return "url(#" + v.dom.containerId + "_" + (l.COLOR ? l.COLOR : "normal") + ")";
        } else {
            return null;
        }
    };
    v.tools.getMarkerUrlHighlighted = function() {
        if (v.conf.showLinkDirection) {
            return "url(#" + v.dom.containerId + "_highlighted)";
        } else {
            return null;
        }
    };

    // on link mouseenter function
    v.tools.onLinkMouseenter = function(link) {
        if (v.conf.showTooltips && link.INFOSTRING) {
            v.tools.showTooltip(link.INFOSTRING);
        }
    };

    // on link mouseleave function
    v.tools.onLinkMouseleave = function() {
        if (v.conf.showTooltips) {
            v.tools.hideTooltip();
        }
    };

    // on node mouse enter function
    v.tools.onNodeMouseenter = function(node) {
        v.main.nodes.classed("highlighted", function(n) {
            return v.tools.neighboring(n, node);
        });
        v.main.links
            .classed("highlighted", function(l) {
                return l.source.ID === node.ID || l.target.ID === node.ID;
            })
            .style("marker-end", function(l) {
                if (l.source.ID === node.ID || l.target.ID === node.ID) {
                    return v.tools.getMarkerUrlHighlighted(l);
                } else {
                    return v.tools.getMarkerUrl(l);
                }
            });
        v.main.selfLinks
            .classed("highlighted", function(l) {
                return l.FROMID === node.ID;
            })
            .style("marker-end", function(l) {
                if (l.source.ID === node.ID || l.target.ID === node.ID) {
                    return v.tools.getMarkerUrlHighlighted(l);
                } else {
                    return v.tools.getMarkerUrl(l);
                }
            });
        if (v.conf.showLabels) {
            v.main.labels.classed("highlighted", function(l) {
                return l.ID === node.ID;
            });
            v.main.labelsCircular.classed("highlighted", function(l) {
                return l.ID === node.ID;
            });
        }
        d3.select(this).classed("highlighted", true);
        v.tools.log("Event node_mouseenter triggered.");
        v.tools.triggerApexEvent(this, "net_gobrechts_d3_force_mouseenter", node);
        if (typeof(v.conf.onNodeMouseenterFunction) === "function") {
            v.conf.onNodeMouseenterFunction.call(this, d3.event, node);
        }
        if (v.conf.showTooltips && node.INFOSTRING) {
            v.tools.showTooltip(node.INFOSTRING);
        }
    };

    // on node mouse leave function
    v.tools.onNodeMouseleave = function(node) {
        v.main.nodes.classed("highlighted", false);
        v.main.links
            .classed("highlighted", false)
            .style("marker-end", v.tools.getMarkerUrl);
        v.main.selfLinks
            .classed("highlighted", false)
            .style("marker-end", v.tools.getMarkerUrl);
        if (v.conf.showLabels) {
            v.main.labels.classed("highlighted", false);
            v.main.labelsCircular.classed("highlighted", false);
        }
        v.tools.log("Event node_mouseleave triggered.");
        v.tools.triggerApexEvent(this, "net_gobrechts_d3_force_mouseleave", node);
        if (typeof(v.conf.onNodeMouseleaveFunction) === "function") {
            v.conf.onNodeMouseleaveFunction.call(this, d3.event, node);
        }
        if (v.conf.showTooltips) {
            v.tools.hideTooltip();
        }
    };

    // on node click function
    v.tools.onNodeClick = function(node) {
        if (d3.event.defaultPrevented) { // ignore drag
            return null;
        } else {
            if (node.LINK && v.conf.nodeEventToOpenLink === "click") {
                v.tools.openLink(node);
            }
            if (v.conf.nodeEventToStopPinMode === "click") {
                d3.select(this).classed("fixed", node.fixed = 0);
            }
            v.tools.log("Event node_click triggered.");
            v.tools.triggerApexEvent(this, "net_gobrechts_d3_force_click", node);
            if (typeof(v.conf.onNodeClickFunction) === "function") {
                v.conf.onNodeClickFunction.call(this, d3.event, node);
            }
        }
    };

    // on node double click function
    v.tools.onNodeDblclick = function(node) {
        if (node.LINK && v.conf.nodeEventToOpenLink === "dblclick") {
            v.tools.openLink(node);
        }
        if (v.conf.nodeEventToStopPinMode === "dblclick") {
            d3.select(this).classed("fixed", node.fixed = 0);
        }
        v.tools.log("Event node_dblclick triggered.");
        v.tools.triggerApexEvent(this, "net_gobrechts_d3_force_dblclick", node);
        if (typeof(v.conf.onNodeDblclickFunction) === "function") {
            v.conf.onNodeDblclickFunction.call(this, d3.event, node);
        }
    };

    // on node contextmenu function
    v.tools.onNodeContextmenu = function(node) {
        if (v.conf.onNodeContextmenuPreventDefault) {
            d3.event.preventDefault();
        }
        if (node.LINK && v.conf.nodeEventToOpenLink === "contextmenu") {
            v.tools.openLink(node);
        }
        if (v.conf.nodeEventToStopPinMode === "contextmenu") {
            d3.select(this).classed("fixed", node.fixed = 0);
        }
        v.tools.log("Event node_contextmenu triggered.");
        v.tools.triggerApexEvent(this, "net_gobrechts_d3_force_contextmenu", node);
        if (typeof(v.conf.onNodeContextmenuFunction) === "function") {
            v.conf.onNodeContextmenuFunction.call(this, d3.event, node);
        }
    };

    // on lasso start function
    v.tools.onLassoStart = function(nodes) {
        var data = {};
        data.numberOfSelectedNodes = 0;
        data.idsOfSelectedNodes = null;
        data.numberOfNodes = nodes.size();
        data.nodes = nodes;
        v.tools.log("Event lasso_start triggered.");
        v.tools.triggerApexEvent(document.querySelector("#" + v.dom.containerId),
            "net_gobrechts_d3_force_lassostart",
            data
        );
        if (typeof(v.conf.onLassoStartFunction) === "function") {
            v.conf.onLassoStartFunction.call(v.dom.svg, d3.event, data);
        }
    };

    // on lasso end function
    v.tools.onLassoEnd = function(nodes) {
        var data = {};
        data.numberOfSelectedNodes = 0;
        data.idsOfSelectedNodes = "";
        data.numberOfNodes = nodes.size();
        data.nodes = nodes;
        nodes.each(function(n) {
            if (n.selected) {
                data.idsOfSelectedNodes += (n.ID + ":");
                data.numberOfSelectedNodes++;
            }
        });
        data.idsOfSelectedNodes =
            (data.idsOfSelectedNodes.length > 0 ?
                data.idsOfSelectedNodes.substr(0, data.idsOfSelectedNodes.length - 1) :
                null);
        v.tools.log("Event lasso_end triggered.");
        v.tools.triggerApexEvent(document.querySelector("#" + v.dom.containerId),
            "net_gobrechts_d3_force_lassoend", data);
        if (typeof(v.conf.onLassoEndFunction) === "function") {
            v.conf.onLassoEndFunction.call(v.dom.svg, d3.event, data);
        }
    };

    // get offset for an element relative to the document: http://javascript.info/tutorial/coordinates
    v.tools.getOffsetRect = function(elem) {
        var box = elem.getBoundingClientRect();
        var body = document.body;
        var docElem = document.documentElement;
        var scrollTop = window.pageYOffset || docElem.scrollTop || body.scrollTop;
        var scrollLeft = window.pageXOffset || docElem.scrollLeft || body.scrollLeft;
        var clientTop = docElem.clientTop || body.clientTop || 0;
        var clientLeft = docElem.clientLeft || body.clientLeft || 0;
        var top = box.top + scrollTop - clientTop;
        var left = box.left + scrollLeft - clientLeft;
        return {
            top: Math.round(top),
            left: Math.round(left)
        };
    };

    // create legend
    v.tools.createLegend = function() {
        v.data.distinctNodeColorValues.forEach(function(colorString, i) {
            var color = colorString.split(";");
            v.dom.legend
                .append("circle")
                .attr("cx", 11)
                .attr("cy", v.conf.height - ((i + 1) * 14 - 3))
                .attr("r", 6)
                .attr("fill", v.tools.color(color[1]));
            v.dom.legend
                .append("text")
                .attr("x", 21)
                .attr("y", v.conf.height - ((i + 1) * 14 - 6))
                .text((color[0] ? color[0] : color[1]));
        });
    };

    // remove legend
    v.tools.removeLegend = function() {
        v.dom.legend.selectAll("*").remove();
    };

    // write conf object into customization wizard
    v.tools.writeConfObjectIntoWizard = function() {
        if (v.status.customize) {
            v.dom.customizeConfObject.text(JSON.stringify(graph.optionsCustomizationWizard(), null, "  "));
        }
    };

    // create customize link
    v.tools.createCustomizeLink = function() {
        if (!v.status.customize &&
            (v.conf.debug || document.querySelector("#apex-dev-toolbar") || document.querySelector("#apexDevToolbar"))
        ) {
            if (document.querySelector("#d3-force-customize-link") === null) {
                v.dom.svg.append("svg:text")
                    .attr("id", "d3-force-customize-link")
                    .attr("class", "link")
                    .attr("x", 5)
                    .attr("y", 15)
                    .attr("text-anchor", "start")
                    .text("Customize Me")
                    .on("click", function() {
                        graph.customize(true);
                    });
            }
        }
    };

    // remove customize link
    v.tools.removeCustomizeLink = function() {
        v.dom.svg.select("#d3-force-customize-link").remove();
    };

    // dragability for customizing container
    v.tools.customizeDrag = d3.behavior.drag()
        .on("dragstart", function() {
            var mouseToBody = d3.mouse(document.body);
            v.dom.customizePosition = v.tools.getOffsetRect(document.querySelector("#" + v.dom.containerId +
                "_customizing"));
            v.dom.customizePosition.mouseLeft = mouseToBody[0] - v.dom.customizePosition.left;
            v.dom.customizePosition.mouseTop = mouseToBody[1] - v.dom.customizePosition.top;
        })
        .on("drag", function() {
            var mouseToBody = d3.mouse(document.body);
            v.dom.customize
                .style("left", Math.max(0,
                    mouseToBody[0] - v.dom.customizePosition.mouseLeft) + "px")
                .style("top", Math.max(0,
                    mouseToBody[1] - v.dom.customizePosition.mouseTop) + "px");
        })
        .on("dragend", function() {
            //v.dom.customizePosition = v.tools.getOffsetRect(document.querySelector("#" + v.dom.containerId +
            //"_customizing"));
            v.dom.customizePosition = v.tools.getOffsetRect(v.dom.customize.node());
        });

    // create customize wizard, if graph not rendering
    v.tools.createCustomizeWizardIfNotRendering = function() {
        if (v.status.customize && !v.status.graphRendering) {
            v.tools.createCustomizeWizard();
        }
    };

    // customize wizard
    v.tools.createCustomizeWizard = function() {
        /* jshint -W074, -W071 */
        var grid, gridRow, gridCell, row, td, form, i = 4,
            currentOption, valueInOptions, key;
        var releaseFixedNodesAndResume = function() {
            graph.releaseFixedNodes().resume();
        };
        var onSelectChange = function() {
            v.status.customizeCurrentTabPosition = this.id;
            if (v.confDefaults[this.name].type === "text") {
                graph[this.name](this.options[this.selectedIndex].value).render();
            } else if (v.confDefaults[this.name].type === "number") {
                graph[this.name](parseFloat(this.options[this.selectedIndex].value)).render();
            } else if (v.confDefaults[this.name].type === "bool") {
                graph[this.name]((this.options[this.selectedIndex].value === "true")).render();
            }
        };
        var appendOptionsToSelect = function(key) {
            v.confDefaults[key].options.forEach(function(option) {
                currentOption = option;
                form.append("option")
                    .attr("value", option)
                    .attr("selected", function() {
                        if (v.confDefaults[key].type === "text" || v.confDefaults[key].type === "bool") {
                            if (currentOption === v.conf[key]) {
                                valueInOptions = true;
                                return "selected";
                            } else {
                                return null;
                            }
                        } else if (v.confDefaults[key].type === "number") {
                            if (parseFloat(currentOption) === v.conf[key]) {
                                valueInOptions = true;
                                return "selected";
                            } else {
                                return null;
                            }
                        }
                    })
                    .text(option);
            });
        };
        // render customization wizard only if we have the right status, otherwise remove the wizard
        if (!v.status.customize) {
            v.tools.removeCustomizeWizard();
            v.tools.createCustomizeLink();
        } else {
            v.tools.removeCustomizeLink();
            // set initial position
            if (!v.dom.customizePosition) {
                v.dom.customizePosition = v.tools.getOffsetRect(v.dom.svg.node());
                v.dom.customizePosition.left = v.dom.customizePosition.left + v.conf.width + 8;
            }
            if (document.querySelector("#" + v.dom.containerId + "_customizing") !== null) {
                v.dom.customize.remove();
            }
            v.dom.customize = v.dom.body.insert("div")
                .attr("id", v.dom.containerId + "_customizing")
                .attr("class", "net_gobrechts_d3_force_customize")
                .style("left", v.dom.customizePosition.left + "px")
                .style("top", v.dom.customizePosition.top + "px");
            v.dom.customize.append("span")
                .attr("class", "drag")
                .call(v.tools.customizeDrag)
                .append("span")
                .attr("class", "title")
                .text("Customize \"" + v.dom.containerId + "\"");
            v.dom.customize.append("a")
                .attr("class", "close focus")
                .attr("tabindex", 1)
                .text("Close")
                .on("click", function() {
                    v.status.customize = false;
                    v.tools.removeCustomizeWizard();
                    v.tools.createCustomizeLink();
                })
                .on("keydown", function() {
                    if (d3.event.keyCode === 13) {
                        v.status.customize = false;
                        v.tools.removeCustomizeWizard();
                        v.tools.createCustomizeLink();
                    }
                });
            grid = v.dom.customize.append("table");
            gridRow = grid.append("tr");
            gridCell = gridRow.append("td").style("vertical-align", "top");
            v.dom.customizeMenu = gridCell.append("span");
            v.dom.customizeOptionsTable = gridCell.append("table");
            for (key in v.confDefaults) {
                if (v.confDefaults.hasOwnProperty(key) && v.confDefaults[key].display) {
                    i += 1;
                    row = v.dom.customizeOptionsTable.append("tr")
                        .attr("class", v.confDefaults[key].relation + "-related");
                    row.append("td")
                        .attr("class", "label")
                        .html("<a href=\"https://ogobrecht.github.io/d3-force-apex-plugin/module-API.html#." +
                            key + "\" target=\"github_d3_force\" tabindex=\"" + i + 100 + "\">" +
                            key + "</a>");
                    td = row.append("td");
                    form = td.append("select")
                        .attr("id", v.dom.containerId + "_" + key)
                        .attr("name", key)
                        .attr("value", v.conf[key])
                        .attr("tabindex", i + 1)
                        .classed("warning", v.confDefaults[key].internal)
                        .on("change", onSelectChange);
                    valueInOptions = false;
                    appendOptionsToSelect(key);
                    // append current value if not existing in default options
                    if (!valueInOptions) {
                        form.append("option")
                            .attr("value", v.conf[key])
                            .attr("selected", "selected")
                            .text(v.conf[key]);
                        v.confDefaults[key].options.push(v.conf[key]);
                    }
                    // add short link to release all fixed (pinned) nodes
                    if (key === "pinMode") {
                        td.append("a")
                            .text(" release all")
                            .attr("href", null)
                            .on("click", releaseFixedNodesAndResume);
                    }
                }
            }
            v.dom.customizeOptionsTable.style("width", d3.select(v.dom.customizeOptionsTable).node()[0][0].clientWidth +
                "px");
            gridCell.append("span").html("<br>");
            gridCell = gridRow.append("td")
                .style("vertical-align", "top")
                .style("padding-left", "5px");
            gridCell.append("span")
                .html("Your Configuration Object<p style=\"font-size:10px;margin:0;\">" +
                    (v.status.apexPluginId ?
                        "To save your options please copy<br>this to your plugin region attributes.<br>" +
                        "Only non-default options are shown.</p>" :
                        "Use this to initialize your graph.<br>Only non-default options are shown.</p>")
                );
            v.dom.customizeConfObject = gridCell.append("textarea")
                .attr("tabindex", i + 5)
                .attr("readonly", "readonly");
            gridCell.append("span").html("<br><br>Current Positions<br>");
            v.dom.customizePositions = gridCell.append("textarea")
                .attr("tabindex", i + 6)
                .attr("readonly", "readonly")
                .text((v.status.forceRunning ? "Force started - wait for end event to show positions..." :
                    JSON.stringify(graph.positions())));
            gridCell.append("span").html("<br><br>Debug Log (descending)<br>");
            v.dom.customizeLog = gridCell.append("textarea")
                .attr("tabindex", i + 7)
                .attr("readonly", "readonly");
            gridRow = grid.append("tr");
            gridCell = gridRow.append("td")
                .attr("colspan", 2)
                .html("Copyrights:");
            gridRow = grid.append("tr");
            gridCell = gridRow.append("td")
                .attr("colspan", 2)
                .html("<table><tr><td style=\"padding-right:20px;\">" +
                    "<a href=\"https://github.com/ogobrecht/d3-force-apex-plugin\" target=\"_blank\" " +
                    "tabindex=\"" + (i + 8) + "\">D3 Force APEX Plugin</a> (" + v.version +
                    ")<br>Ottmar Gobrecht</td><td style=\"padding-right:20px;\">" +
                    "<a href=\"https://github.com/mbostock/d3\" target=\"d3js_org\" tabindex=\"" + (i + 9) +
                    "\">D3.js</a> (" + d3.version + ") and " +
                    "<a href=\"https://github.com/d3/d3-plugins/tree/master/lasso\" target=\"_blank\" tabindex=\"" +
                    (i + 10) + "\">D3 Lasso Plugin</a> (modified)<br>Mike Bostock" +
                    "</td></tr><tr><td colspan=\"3\">" +
                    "<a href=\"https://github.com/tinker10/D3-Labeler\" target=\"github_d3_labeler\" " +
                    "tabindex=\"" + (i + 11) +
                    "\">D3 Labeler Plugin</a> (automatic label placement using simulated annealing)" +
                    "<br>Evan Wang</td></tr></table>"); // https://github.com/tinker10/D3-Labeler
            v.tools.createCustomizeMenu(v.status.customizeCurrentMenu);
            v.tools.writeConfObjectIntoWizard();
            if (v.status.customizeCurrentTabPosition) {
                document.getElementById(v.status.customizeCurrentTabPosition).focus();
            }
        }
    };

    v.tools.removeCustomizeWizard = function() {
        d3.select("#" + v.dom.containerId + "_customizing").remove();
    };

    v.tools.createCustomizeMenu = function(relation) {
        v.status.customizeCurrentMenu = relation;
        v.dom.customizeMenu.selectAll("*").remove();
        v.dom.customizeMenu.append("span").text("Show options for:");
        if (v.status.customizeCurrentMenu === "nodes") {
            v.dom.customizeMenu.append("span").style("font-weight", "bold").style("margin-left", "10px").text("NODES");
            v.dom.customizeOptionsTable.selectAll("tr.node-related").classed("hidden", false);
            v.dom.customizeOptionsTable.selectAll("tr.label-related,tr.link-related,tr.graph-related")
                .classed("hidden", true);
        } else {
            v.dom.customizeMenu.append("a")
                .style("font-weight", "bold")
                .style("margin-left", "10px")
                .text("NODES")
                .attr("tabindex", 2)
                .on("click", function() {
                    v.tools.createCustomizeMenu("nodes");
                    v.dom.customizeOptionsTable.selectAll("tr.node-related").classed("hidden", false);
                    v.dom.customizeOptionsTable.selectAll("tr.label-related,tr.link-related,tr.graph-related")
                        .classed("hidden", true);
                })
                .on("keydown", function() {
                    if (d3.event.keyCode === 13) {
                        v.tools.createCustomizeMenu("nodes");
                        v.dom.customizeOptionsTable.selectAll("tr.node-related").classed("hidden", false);
                        v.dom.customizeOptionsTable.selectAll("tr.label-related,tr.link-related,tr.graph-related")
                            .classed("hidden", true);
                    }
                });
        }
        if (v.status.customizeCurrentMenu === "labels") {
            v.dom.customizeMenu.append("span").style("font-weight", "bold").style("margin-left", "10px").text("LABELS");
            v.dom.customizeOptionsTable.selectAll("tr.label-related").classed("hidden", false);
            v.dom.customizeOptionsTable.selectAll("tr.node-related,tr.link-related,tr.graph-related")
                .classed("hidden", true);
        } else {
            v.dom.customizeMenu.append("a")
                .style("font-weight", "bold")
                .style("margin-left", "10px")
                .text("LABELS")
                .attr("tabindex", 2)
                .on("click", function() {
                    v.tools.createCustomizeMenu("labels");
                    v.dom.customizeOptionsTable.selectAll("tr.label-related").classed("hidden", false);
                    v.dom.customizeOptionsTable.selectAll("tr.node-related,tr.link-related,tr.graph-related")
                        .classed("hidden", true);
                })
                .on("keydown", function() {
                    if (d3.event.keyCode === 13) {
                        v.tools.createCustomizeMenu("labels");
                        v.dom.customizeOptionsTable.selectAll("tr.label-related").classed("hidden", false);
                        v.dom.customizeOptionsTable.selectAll("tr.node-related,tr.link-related,tr.graph-related")
                            .classed("hidden", true);
                    }
                });
        }
        if (v.status.customizeCurrentMenu === "links") {
            v.dom.customizeMenu.append("span").style("font-weight", "bold").style("margin-left", "10px").text("LINKS");
            v.dom.customizeOptionsTable.selectAll("tr.link-related").classed("hidden", false);
            v.dom.customizeOptionsTable.selectAll("tr.node-related,tr.label-related,tr.graph-related")
                .classed("hidden", true);
        } else {
            v.dom.customizeMenu.append("a")
                .style("font-weight", "bold")
                .style("margin-left", "10px")
                .text("LINKS")
                .attr("tabindex", 3)
                .on("click", function() {
                    v.tools.createCustomizeMenu("links");
                    v.dom.customizeOptionsTable.selectAll("tr.link-related").classed("hidden", false);
                    v.dom.customizeOptionsTable.selectAll("tr.node-related,tr.label-related,tr.graph-related")
                        .classed("hidden", true);
                })
                .on("keydown", function() {
                    if (d3.event.keyCode === 13) {
                        v.tools.createCustomizeMenu("links");
                        v.dom.customizeOptionsTable.selectAll("tr.link-related").classed("hidden", false);
                        v.dom.customizeOptionsTable.selectAll("tr.node-related,tr.label-related,tr.graph-related")
                            .classed("hidden", true);
                    }
                });
        }
        if (v.status.customizeCurrentMenu === "graph") {
            v.dom.customizeMenu.append("span").style("font-weight", "bold").style("margin-left", "10px").text("GRAPH");
            v.dom.customizeOptionsTable.selectAll("tr.graph-related").classed("hidden", false);
            v.dom.customizeOptionsTable.selectAll("tr.node-related,tr.label-related,tr.link-related")
                .classed("hidden", true);
        } else {
            v.dom.customizeMenu.append("a")
                .style("font-weight", "bold")
                .style("margin-left", "10px")
                .text("GRAPH")
                .attr("tabindex", 4)
                .on("click", function() {
                    v.tools.createCustomizeMenu("graph");
                    v.dom.customizeOptionsTable.selectAll("tr.graph-related").classed("hidden", false);
                    v.dom.customizeOptionsTable.selectAll("tr.node-related,tr.label-related,tr.link-related")
                        .classed("hidden", true);
                })
                .on("keydown", function() {
                    if (d3.event.keyCode === 13) {
                        v.tools.createCustomizeMenu("graph");
                        v.dom.customizeOptionsTable.selectAll("tr.graph-related").classed("hidden", false);
                        v.dom.customizeOptionsTable.selectAll("tr.node-related,tr.label-related,tr.link-related")
                            .classed("hidden", true);
                    }
                });
        }
        v.dom.customizeMenu.append("span").html("<br><br>");
    };

    // helper function to wrap text - https://bl.ocks.org/mbostock/7555321
    v.tools.wrapLabels = function(labels, width) {
        labels.each(function(label, i) {
            var text = d3.select(this);
            if (i === 0) {
                v.status.labelFontSize = parseInt(text.style("font-size"));
            }
            if (!this.hasAttribute("lines")) {
                var words = text.text().split(/\s+/).reverse(),
                    word,
                    line = [],
                    lineNumber = 0,
                    lineHeight = v.status.labelFontSize * v.conf.wrappedLabelLineHeight,
                    x = text.attr("x"),
                    y = text.attr("y"),
                    dy = 0,
                    tspan = text.text(null).append("tspan").attr("x", x).attr("y", y).attr("dy", dy + "px");

                while (word = words.pop()) { // jshint ignore:line
                    line.push(word);
                    tspan.text(line.join(" "));
                    if (tspan.node().getComputedTextLength() > width) {
                        line.pop();
                        tspan.text(line.join(" "));
                        line = [word];
                        tspan = text.append("tspan").attr("x", x).attr("y", y).attr("dy", ++lineNumber * lineHeight +
                            dy + "px").text(word);
                    }
                }
                //save number of lines
                text.attr("lines", lineNumber + 1);
            }
        });
    };

    /*******************************************************************************************************************
     * LIBRARIES
     */

    // D3 labeler plugin
    /* Source Code: https://github.com/tinker10/D3-Labeler
    The MIT License (MIT)

    Copyright (c) 2013 Evan Wang

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    */
    v.lib.labelerPlugin = function() {
        /* jshint -W106 */
        var lab = [],
            anc = [],
            w = 1, // box width
            h = 1, // box width
            labeler = {};

        var max_move = 5, //5.0,
            max_angle = 0.5, //0.5,
            acc = 0,
            rej = 0;

        // weights
        var w_len = 0.2, // leader line length
            w_inter = 1.0, // leader line intersection
            w_lab2 = 30.0, // label-label overlap
            w_lab_anc = 30.0, // label-anchor overlap
            w_orient = 1.0; //3.0; // orientation bias

        // booleans for user defined functions
        var user_energy = false,
            user_schedule = false;

        var user_defined_energy,
            user_defined_schedule;

        var energy = function(index) {
            /* jshint -W071 */
            // energy function, tailored for label placement

            var m = lab.length,
                ener = 0,
                dx = lab[index].x - anc[index].x,
                dy = anc[index].y - lab[index].y,
                dist = Math.sqrt(dx * dx + dy * dy),
                overlap = true;

            // penalty for length of leader line
            if (dist > 0) {
                ener += dist * w_len;
            }

            // label orientation bias
            dx /= dist;
            dy /= dist;
            if (dx > 0 && dy > 0) {
                ener += 0;
            } else if (dx < 0 && dy > 0) {
                ener += w_orient;
            } else if (dx < 0 && dy < 0) {
                ener += 2 * w_orient;
            } else {
                ener += 3 * w_orient;
            }

            var x21 = lab[index].x,
                y21 = lab[index].y - lab[index].height + 2.0,
                x22 = lab[index].x + lab[index].width,
                y22 = lab[index].y + 2.0;
            var x11, x12, y11, y12, x_overlap, y_overlap, overlap_area;

            for (var i = 0; i < m; i++) {
                if (i !== index) {

                    // penalty for intersection of leader lines
                    overlap = intersect(anc[index].x, lab[index].x, anc[i].x, lab[i].x,
                        anc[index].y, lab[index].y, anc[i].y, lab[i].y);
                    if (overlap) {
                        ener += w_inter;
                    }

                    // penalty for label-label overlap
                    x11 = lab[i].x;
                    y11 = lab[i].y - lab[i].height + 2.0;
                    x12 = lab[i].x + lab[i].width;
                    y12 = lab[i].y + 2.0;
                    x_overlap = Math.max(0, Math.min(x12, x22) - Math.max(x11, x21));
                    y_overlap = Math.max(0, Math.min(y12, y22) - Math.max(y11, y21));
                    overlap_area = x_overlap * y_overlap;
                    ener += (overlap_area * w_lab2);
                }

                // penalty for label-anchor overlap
                x11 = anc[i].x - anc[i].r;
                y11 = anc[i].y - anc[i].r;
                x12 = anc[i].x + anc[i].r;
                y12 = anc[i].y + anc[i].r;
                x_overlap = Math.max(0, Math.min(x12, x22) - Math.max(x11, x21));
                y_overlap = Math.max(0, Math.min(y12, y22) - Math.max(y11, y21));
                overlap_area = x_overlap * y_overlap;
                ener += (overlap_area * w_lab_anc);

            }
            return ener;
        };

        var mcmove = function(currT) {
            // Monte Carlo translation move

            // select a random label
            var i = Math.floor(Math.random() * lab.length);

            // save old coordinates
            var x_old = lab[i].x;
            var y_old = lab[i].y;

            // old energy
            var old_energy;
            if (user_energy) {
                old_energy = user_defined_energy(i, lab, anc);
            } else {
                old_energy = energy(i);
            }

            // random translation
            lab[i].x += (Math.random() - 0.5) * max_move;
            lab[i].y += (Math.random() - 0.5) * max_move;

            // hard wall boundaries
            if (lab[i].x > w) {
                lab[i].x = x_old;
            }
            if (lab[i].x < 0) {
                lab[i].x = x_old;
            }
            if (lab[i].y > h) {
                lab[i].y = y_old;
            }
            if (lab[i].y < 0) {
                lab[i].y = y_old;
            }

            // new energy
            var new_energy;
            if (user_energy) {
                new_energy = user_defined_energy(i, lab, anc);
            } else {
                new_energy = energy(i);
            }

            // delta E
            var delta_energy = new_energy - old_energy;

            if (Math.random() < Math.exp(-delta_energy / currT)) {
                acc += 1;
            } else {
                // move back to old coordinates
                lab[i].x = x_old;
                lab[i].y = y_old;
                rej += 1;
            }

        };

        var mcrotate = function(currT) {
            /* jshint -W071 */
            // Monte Carlo rotation move

            // select a random label
            var i = Math.floor(Math.random() * lab.length);

            // save old coordinates
            var x_old = lab[i].x;
            var y_old = lab[i].y;

            // old energy
            var old_energy;
            if (user_energy) {
                old_energy = user_defined_energy(i, lab, anc);
            } else {
                old_energy = energy(i);
            }

            // random angle
            var angle = (Math.random() - 0.5) * max_angle;

            var s = Math.sin(angle);
            var c = Math.cos(angle);

            // translate label (relative to anchor at origin):
            lab[i].x -= anc[i].x;
            lab[i].y -= anc[i].y;

            // rotate label
            var x_new = lab[i].x * c - lab[i].y * s,
                y_new = lab[i].x * s + lab[i].y * c;

            // translate label back
            lab[i].x = x_new + anc[i].x;
            lab[i].y = y_new + anc[i].y;

            // hard wall boundaries
            if (lab[i].x > w) {
                lab[i].x = x_old;
            }
            if (lab[i].x < 0) {
                lab[i].x = x_old;
            }
            if (lab[i].y > h) {
                lab[i].y = y_old;
            }
            if (lab[i].y < 0) {
                lab[i].y = y_old;
            }

            // new energy
            var new_energy;
            if (user_energy) {
                new_energy = user_defined_energy(i, lab, anc);
            } else {
                new_energy = energy(i);
            }

            // delta E
            var delta_energy = new_energy - old_energy;

            if (Math.random() < Math.exp(-delta_energy / currT)) {
                acc += 1;
            } else {
                // move back to old coordinates
                lab[i].x = x_old;
                lab[i].y = y_old;
                rej += 1;
            }

        };

        var intersect = function(x1, x2, x3, x4, y1, y2, y3, y4) { // jshint ignore:line
            // returns true if two lines intersect, else false
            // from http://paulbourke.net/geometry/lineline2d/

            var mua, mub;
            var denom, numera, numerb;

            denom = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1);
            numera = (x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3);
            numerb = (x2 - x1) * (y1 - y3) - (y2 - y1) * (x1 - x3);

            /* Is the intersection along the the segments */
            mua = numera / denom;
            mub = numerb / denom;
            return !(mua < 0 || mua > 1 || mub < 0 || mub > 1);

        };

        var cooling_schedule = function(currT, initialT, nsweeps) {
            // linear cooling
            return (currT - (initialT / nsweeps));
        };

        labeler.start = function(nsweeps) {
            // main simulated annealing function
            var m = lab.length,
                currT = 1.0,
                initialT = 1.0;

            for (var i = 0; i < nsweeps; i++) {
                for (var j = 0; j < m; j++) {
                    if (Math.random() < 0.5) {
                        mcmove(currT);
                    } else {
                        mcrotate(currT);
                    }
                }
                currT = cooling_schedule(currT, initialT, nsweeps);
            }
        };

        labeler.width = function(x) {
            // users insert graph width
            if (!arguments.length) {
                return w;
            }
            w = x;
            return labeler;
        };

        labeler.height = function(x) {
            // users insert graph height
            if (!arguments.length) {
                return h;
            }
            h = x;
            return labeler;
        };

        labeler.label = function(x) {
            // users insert label positions
            if (!arguments.length) {
                return lab;
            }
            lab = x;
            return labeler;
        };

        labeler.anchor = function(x) {
            // users insert anchor positions
            if (!arguments.length) {
                return anc;
            }
            anc = x;
            return labeler;
        };

        labeler.alt_energy = function(x) {
            // user defined energy
            if (!arguments.length) {
                return energy;
            }
            user_defined_energy = x;
            user_energy = true;
            return labeler;
        };

        labeler.alt_schedule = function(x) {
            // user defined cooling_schedule
            if (!arguments.length) {
                return cooling_schedule;
            }
            user_defined_schedule = x;
            user_schedule = true;
            return labeler;
        };

        return labeler;
    };

    // D3 lasso plugin
    /* Source Code: https://github.com/d3/d3-plugins/blob/master/lasso/lasso.js
    Copyright (c) 2012-2014, Michael Bostock
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this
      list of conditions and the following disclaimer.

    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.

    * The name Michael Bostock may not be used to endorse or promote products
      derived from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL MICHAEL BOSTOCK BE LIABLE FOR ANY DIRECT,
    INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
    OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
    NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
    EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    */
    v.lib.lassoPlugin = function() {
        /* jshint -W040, -W106 */
        var items = null,
            closePathDistance = 75,
            closePathSelect = true,
            isPathClosed = false,
            hoverSelect = true,
            area = null,
            pathContainer = null,
            on = {
                start: function() {},
                draw: function() {},
                end: function() {}
            };

        function lasso() {
            var _this = d3.select(this[0][0]);
            /* START MODIFICATION ------------------------------------------------------>
             * Reuse lasso path group element, if possible. In my D3 force implementation
             * I provide the possibility to enable or disable the lasso. After enabling
             * the lasso I get always a new lasso element. I prefer to reuse the existing
             * one.
             * */
            //
            var g, dyn_path, close_path, complete_path, path, origin, last_known_point, path_length_start, drag;
            pathContainer = pathContainer || _this; // if not set then defaults to _this
            if (pathContainer.selectAll("g.lasso").size() === 0) {
                g = pathContainer.append("g").attr("class", "lasso");
                dyn_path = g.append("path").attr("class", "drawn");
                close_path = g.append("path").attr("class", "loop_close");
                complete_path = g.append("path").attr("class", "complete_path").attr("display", "none");
            } else {
                g = pathContainer.select("g.lasso");
                dyn_path = g.select("path.drawn");
                close_path = g.select("path.loop_close");
                complete_path = g.select("path.complete_path");
            }
            /* <-------------------------------------------------------- END MODIFICATION */

            function dragstart() {
                // Reset blank lasso path
                path = "";
                dyn_path.attr("d", null);
                close_path.attr("d", null);
                // Set path length start
                path_length_start = 0;
                // Set every item to have a false selection and reset their center point and counters
                items[0].forEach(function(d) {
                    d.hoverSelected = false;
                    d.loopSelected = false;
                    var cur_box = d.getBBox();
                    /* START MODIFICATION ------------------------------------------------------>
                     * Implement correct values after zoom and pan based on the following article:
                     * http://stackoverflow.com/questions/18554224/getting-screen-positions-of-d3-nodes-after-transform
                     * */
                    var ctm = d.getCTM();
                    d.lassoPoint = {
                        cx: Math.round((cur_box.x + cur_box.width / 2) * ctm.a + ctm.e),
                        cy: Math.round((cur_box.y + cur_box.height / 2) * ctm.d + ctm.f),
                        /* <-------------------------------------------------------- END MODIFICATION */
                        edges: {
                            top: 0,
                            right: 0,
                            bottom: 0,
                            left: 0
                        },
                        close_edges: {
                            left: 0,
                            right: 0
                        }
                    };
                });

                // if hover is on, add hover function
                if (hoverSelect === true) {
                    items.on("mouseover.lasso", function() {
                        // if hovered, change lasso selection attribute to true
                        d3.select(this)[0][0].hoverSelected = true;
                    });
                }

                // Run user defined start function
                on.start();
            }

            function dragmove() {
                /* jshint -W071 */
                var x = d3.mouse(this)[0],
                    y = d3.mouse(this)[1],
                    distance,
                    close_draw_path,
                    complete_path_d,
                    close_path_node,
                    close_path_length,
                    close_path_edges,
                    path_node,
                    path_length_end,
                    i,
                    last_pos,
                    prior_pos,
                    prior_pos_obj,
                    cur_pos,
                    cur_pos_obj,
                    calcLassoPointEdges = function(d) {
                        if (cur_pos_obj.x > d.lassoPoint.cx) {
                            d.lassoPoint.edges.right = d.lassoPoint.edges.right + 1;
                        }
                        if (cur_pos_obj.x < d.lassoPoint.cx) {
                            d.lassoPoint.edges.left = d.lassoPoint.edges.left + 1;
                        }
                    },
                    calcLassoPointCloseEdges = function(d) {
                        if (Math.round(cur_pos.y) !== Math.round(prior_pos.y) &&
                            Math.round(cur_pos.x) > d.lassoPoint.cx) {
                            d.lassoPoint.close_edges.right = 1;
                        }
                        if (Math.round(cur_pos.y) !== Math.round(prior_pos.y) &&
                            Math.round(cur_pos.x) < d.lassoPoint.cx) {
                            d.lassoPoint.close_edges.left = 1;
                        }
                    },
                    ckeckIfNodeYequalsCurrentPosY = function(d) {
                        return d.lassoPoint.cy === Math.round(cur_pos.y);
                    },
                    ckeckIfNodeYequalsCurrentPriorPosY = function(d) {
                        var a;
                        if (d.lassoPoint.cy === cur_pos_obj.y && d.lassoPoint.cy !== prior_pos_obj.y) {
                            last_known_point = {
                                x: prior_pos_obj.x,
                                y: prior_pos_obj.y
                            };
                            a = false;
                        } else if (d.lassoPoint.cy === cur_pos_obj.y && d.lassoPoint.cy === prior_pos_obj.y) {
                            a = false;
                        } else if (d.lassoPoint.cy === prior_pos_obj.y && d.lassoPoint.cy !== cur_pos_obj.y) {
                            a = sign(d.lassoPoint.cy - cur_pos_obj.y) !== sign(d.lassoPoint.cy - last_known_point.y);
                        } else {
                            last_known_point = {
                                x: prior_pos_obj.x,
                                y: prior_pos_obj.y
                            };
                            a = sign(d.lassoPoint.cy - cur_pos_obj.y) !== sign(d.lassoPoint.cy - prior_pos_obj.y);
                        }
                        return a;
                    };

                // Initialize the path or add the latest point to it
                if (path === "") {
                    path = path + "M " + x + " " + y;
                    origin = [x, y];
                } else {
                    path = path + " L " + x + " " + y;
                }

                // Reset closed edges counter
                items[0].forEach(function(d) {
                    d.lassoPoint.close_edges = {
                        left: 0,
                        right: 0
                    };
                });

                // Calculate the current distance from the lasso origin
                distance = Math.sqrt(Math.pow(x - origin[0], 2) + Math.pow(y - origin[1], 2));

                // Set the closed path line
                close_draw_path = "M " + x + " " + y + " L " + origin[0] + " " + origin[1];

                // Draw the lines
                dyn_path.attr("d", path);

                // If within the closed path distance parameter, show the closed path. otherwise, hide it
                if (distance <= closePathDistance) {
                    close_path.attr("display", null);
                } else {
                    close_path.attr("display", "none");
                }

                isPathClosed = distance <= closePathDistance;

                // create complete path
                complete_path_d = d3.select("path")[0][0].attributes.d.value + "Z";
                complete_path.attr("d", complete_path_d);

                // get path length
                path_node = dyn_path.node();
                path_length_end = path_node.getTotalLength();
                last_pos = path_node.getPointAtLength(path_length_start - 1);

                for (i = path_length_start; i <= path_length_end; i++) {
                    cur_pos = path_node.getPointAtLength(i);
                    cur_pos_obj = {
                        x: Math.round(cur_pos.x * 100) / 100,
                        y: Math.round(cur_pos.y * 100) / 100
                    };
                    prior_pos = path_node.getPointAtLength(i - 1);
                    prior_pos_obj = {
                        x: Math.round(prior_pos.x * 100) / 100,
                        y: Math.round(prior_pos.y * 100) / 100
                    };

                    items[0].filter(ckeckIfNodeYequalsCurrentPriorPosY).forEach(calcLassoPointEdges);
                }

                if (isPathClosed === true && closePathSelect === true) {
                    close_path.attr("d", close_draw_path);
                    close_path_node = close_path.node();
                    close_path_length = close_path_node.getTotalLength();
                    close_path_edges = {
                        left: 0,
                        right: 0
                    };
                    for (i = 0; i <= close_path_length; i++) {
                        cur_pos = close_path_node.getPointAtLength(i);
                        prior_pos = close_path_node.getPointAtLength(i - 1);
                        items[0].filter(ckeckIfNodeYequalsCurrentPosY).forEach(calcLassoPointCloseEdges);
                    }
                    items[0].forEach(function(a) {
                        if ((a.lassoPoint.edges.left + a.lassoPoint.close_edges.left) > 0 &&
                            (a.lassoPoint.edges.right + a.lassoPoint.close_edges.right) % 2 === 1) {
                            a.loopSelected = true;
                        } else {
                            a.loopSelected = false;
                        }
                    });
                } else {
                    items[0].forEach(function(d) {
                        d.loopSelected = false;
                    });
                }

                // Tag possible items
                d3.selectAll(items[0].filter(function(d) {
                        return (d.loopSelected && isPathClosed) || d.hoverSelected;
                    }))
                    .attr("d", function(d) {
                        d.possible = true;
                        return d.possible;
                    });

                d3.selectAll(items[0].filter(function(d) {
                        return !((d.loopSelected && isPathClosed) || d.hoverSelected);
                    }))
                    .attr("d", function(d) {
                        d.possible = false;
                        return d.possible;
                    });

                on.draw();

                // Continue drawing path from where it left off
                path_length_start = path_length_end + 1;
            }

            function dragend() {
                // Remove mouseover tagging function
                items.on("mouseover.lasso", null);

                // Tag selected items
                items.filter(function(d) {
                        return d.possible === true;
                    })
                    .attr("d", function(d) {
                        d.selected = true;
                        return d.selected;
                    });

                items.filter(function(d) {
                        return d.possible === false;
                    })
                    .attr("d", function(d) {
                        d.selected = false;
                        return d.selected;
                    });

                // Reset possible items
                items.attr("d", function(d) {
                    d.possible = false;
                    return d.possible;
                });

                // Clear lasso
                dyn_path.attr("d", null);
                close_path.attr("d", null);

                // Run user defined end function
                on.end();

            }
            drag = d3.behavior.drag()
                .on("dragstart", dragstart)
                .on("drag", dragmove)
                .on("dragend", dragend);
            area.call(drag);
        }

        lasso.items = function(_) {

            if (!arguments.length) {
                return items;
            }
            items = _;
            items[0].forEach(function(d) {
                var item = d3.select(d);
                if (typeof item.datum() === "undefined") {
                    item.datum({
                        possible: false,
                        selected: false
                    });
                } else {
                    item.attr("d", function(e) {
                        e.possible = false;
                        e.selected = false;
                        return e;
                    });
                }
            });
            return lasso;
        };

        lasso.closePathDistance = function(_) {
            if (!arguments.length) {
                return closePathDistance;
            }
            closePathDistance = _;
            return lasso;
        };

        lasso.closePathSelect = function(_) {
            if (!arguments.length) {
                return closePathSelect;
            }
            closePathSelect = _ === true;
            return lasso;
        };

        lasso.isPathClosed = function(_) {
            if (!arguments.length) {
                return isPathClosed;
            }
            isPathClosed = _ === true;
            return lasso;
        };

        lasso.hoverSelect = function(_) {
            if (!arguments.length) {
                return hoverSelect;
            }
            hoverSelect = _ === true;
            return lasso;
        };

        lasso.on = function(type, _) {
            if (!arguments.length) {
                return on;
            }
            if (arguments.length === 1) {
                return on[type];
            }
            var types = ["start", "draw", "end"];
            if (types.indexOf(type) > -1) {
                on[type] = _;
            }
            return lasso;
        };

        lasso.area = function(_) {
            if (!arguments.length) {
                return area;
            }
            area = _;
            return lasso;
        };

        /* START MODIFICATION ------------------------------------------------------>
         * Allow different container for lasso path than area, where lasso can be started
         * */
        lasso.pathContainer = function(_) {
            if (!arguments.length) {
                return pathContainer;
            }
            pathContainer = d3.select(_[0][0]);
            return lasso;
        };
        /* <-------------------------------------------------------- END MODIFICATION */

        function sign(x) { // jshint ignore:line
            return x ? x < 0 ? -1 : 1 : 0;
        }

        return lasso;
    };


    /*******************************************************************************************************************
     * MAIN
     */

    v.main.init();


    /*******************************************************************************************************************
     * PUBLIC GRAPH FUNCTION AND API METHODS
     */

    // public start function: get data and start visualization
    /**
     * This method starts the graph. You can configure your graph with all the available methods, but without the `start` method your changes will NOT take into effect.
     *
     * You can pass new data (see {@tutorial included-sample-data}) to the `start` method. Data can be a XML string, JSON string or JavaScript object (JSON). If you use the APEX plugin, then the `start` method internally does the AJAX call to your Oracle database, but you can prevent this behavior by passing data to this method.
     *
     * This also means, that you can use data from a textarea or a report for the APEX plugin, to overwrite the existing data and you do not need to configure any query to run this plugin. If you do so and you do not pass data to the `start` method on the very first call, then the plugin provides sample data - it is the same data with the [APEX online demo](https://apex.oracle.com/pls/apex/f?p=18290:1) of this plugin, there is no query configured and you get therefore the sampledata :-)
     * @see {@link module:API.render}
     * @see {@link module:API.resume}
     * @param {(string|Object)} [data=Sample data EMP table flavoured] - Can be a XML string, JSON string or JavaScript object (JSON)
     * @returns {Object} The graph object for method chaining.
     */
    graph.start = function(data) {
        var firstChar;
        // try to use the input data - this means also, we can overwrite the data from APEX with raw data (textarea or
        // whatever you like...)
        if (data) {
            graph.render(data);
        }
        // if we have no data, then we try to use the APEX context (if APEX plugin ID is set)
        else if (v.status.apexPluginId) {
            if (v.conf.showLoadingIndicatorOnAjaxCall) {
                graph.showLoadingIndicator(true);
            }
            apex.server.plugin(
                v.status.apexPluginId, {
                    p_debug: $v("pdebug"), //jshint ignore:line
                    pageItems: v.status.apexPageItemsToSubmit
                }, {
                    success: function(dataString) {
                        // dataString starts NOT with "<" or "{", when there are no queries defined in APEX or
                        // when the queries returns empty data or when a error occurs on the APEX backend side
                        if (v.conf.showLoadingIndicatorOnAjaxCall) {
                            graph.showLoadingIndicator(false);
                        }
                        firstChar = dataString.trim().substr(0, 1);
                        if (firstChar === "<" || firstChar === "{") {
                            graph.render(dataString);
                        } else if (dataString.trim().substr(0, 16) === "no_query_defined") {
                            // this will keep the old data or using the sample data, if no old data existing
                            graph.render();
                            v.tools.logError("No query defined.");
                        } else if (dataString.trim().substr(0, 22) === "query_returned_no_data") {
                            graph.render({
                                "data": {
                                    "nodes": [{
                                        "ID": "1",
                                        "LABEL": "ERROR: No data.",
                                        "COLORVALUE": "1",
                                        "SIZEVALUE": "1"
                                    }],
                                    "links": []
                                }
                            });
                            v.tools.logError("Query returned no data.");
                        } else {
                            graph.render({
                                "data": {
                                    "nodes": [{
                                        "ID": "1",
                                        "LABEL": "ERROR: " + dataString + ".",
                                        "COLORVALUE": "1",
                                        "SIZEVALUE": "1"
                                    }],
                                    "links": []
                                }
                            });
                            v.tools.logError(dataString);
                        }
                    },
                    error: function(xhr, status, errorThrown) {
                        graph.render({
                            "data": {
                                "nodes": [{
                                    "ID": "1",
                                    "LABEL": "AJAX call terminated with errors.",
                                    "COLORVALUE": "1",
                                    "SIZEVALUE": "1"
                                }],
                                "links": []
                            }
                        });
                        v.tools.logError("AJAX call terminated with errors: " + errorThrown + ".");
                    },
                    dataType: "text"
                }
            );
        }
        // if we have no raw data and no APEX context, then we start to render without data (the render function will
        // then provide sample data)
        else {
            graph.render();
        }
        return graph;
    };
    /**
     * The `render` method does the same as the `start` method - the only difference is, that the `render` method does not try to load data, if you use the APEX plugin. You can use this method after changing options which need a `render` cycle to take the changes into effect:
     *
     *     example.minNodeRadius(4).maxNodeRadius(20).render();
     * @see {@link module:API.start}
     * @see {@link module:API.resume}
     * @param {(string|Object)} [data=Sample data EMP table flavoured] - Can be a XML string, JSON string or JavaScript object (JSON)
     * @returns {Object} The graph object for method chaining.
     */
    graph.render = function(data) {
        /* jshint -W074, -W071 */
        var message;
        v.status.graphStarted = true;
        v.status.graphRendering = true;

        v.tools.triggerApexEvent(document.querySelector("#" + v.dom.containerId), "apexbeforerefresh");

        // if we start the rendering the first time and there is no input data, then provide sample data
        if (!data && !v.status.graphReady) {
            v.tools.logError("Houston, we have a problem - we have to provide sample data.");
            v.status.sampleData = true;
            data = v.data.sampleData;
        } else if (data) {
            v.status.sampleData = false;
        }

        // if we have incoming data, than we do our transformations here, otherwise we use the existing data
        if (data) {

            if (v.status.graphReady) {
                v.status.graphOldPositions = graph.positions();
            }

            // data is an object
            if (data.constructor === Object) {
                v.data.dataConverted = data;
                if (v.conf.debug) {
                    v.tools.log("Data object:");
                    v.tools.log(v.data.dataConverted, true);
                }
            }
            // data is a string
            else if (data.constructor === String) {
                // convert incoming data depending on type
                if (data.trim().substr(0, 1) === "<") {
                    try {
                        v.data.dataConverted = v.tools.xmlToJson(v.tools.parseXml(data));
                        if (v.data.dataConverted === null) {
                            message = "Unable to convert XML string.";
                            v.tools.logError(message);
                            v.data.dataConverted = {
                                "data": {
                                    "nodes": [{
                                        "ID": "1",
                                        "LABEL": "ERROR: " + message,
                                        "COLORVALUE": "1",
                                        "SIZEVALUE": "1"
                                    }],
                                    "links": []
                                }
                            };
                        }
                    } catch (e) {
                        message = "Unable to convert XML string: " + e.message + ".";
                        v.tools.logError(message);
                        v.data.dataConverted = {
                            "data": {
                                "nodes": [{
                                    "ID": "1",
                                    "LABEL": "ERROR: " + message,
                                    "COLORVALUE": "1",
                                    "SIZEVALUE": "1"
                                }],
                                "links": []
                            }
                        };
                    }
                } else if (data.trim().substr(0, 1) === "{") {
                    try {
                        v.data.dataConverted = JSON.parse(data);
                    } catch (e) {
                        message = "Unable to parse JSON string: " + e.message + ".";
                        v.tools.logError(message);
                        v.data.dataConverted = {
                            "data": {
                                "nodes": [{
                                    "ID": "1",
                                    "LABEL": "ERROR: " + message,
                                    "COLORVALUE": "1",
                                    "SIZEVALUE": "1"
                                }],
                                "links": []
                            }
                        };
                    }
                } else {
                    message = "Your data string is not starting with \"<\" or \"{\" - parsing not possible.";
                    v.tools.logError(message);
                    v.data.dataConverted = {
                        "data": {
                            "nodes": [{
                                "ID": "1",
                                "LABEL": "ERROR: " + message,
                                "COLORVALUE": "1",
                                "SIZEVALUE": "1"
                            }],
                            "links": []
                        }
                    };
                }
                if (v.conf.debug) {
                    v.tools.log("Data string:");
                    v.tools.log(data, true);
                    v.tools.log("Converted data object:");
                    v.tools.log(v.data.dataConverted, true);
                }
            }
            // data has unknown format
            else {
                message = "Unable to parse your data - input data can be a XML string, " +
                    "JSON string or JavaScript object.";
                v.tools.logError(message);
                v.data.dataConverted = {
                    "data": {
                        "nodes": [{
                            "ID": "1",
                            "LABEL": "ERROR: " + message,
                            "COLORVALUE": "1",
                            "SIZEVALUE": "1"
                        }],
                        "links": []
                    }
                };
            }

            // create references to our new data
            if (v.data.dataConverted !== null) {
                if (v.data.dataConverted.hasOwnProperty("data") && v.data.dataConverted.data !== null) {
                    if (v.data.dataConverted.data.hasOwnProperty("nodes") && v.data.dataConverted.data.nodes !== null) {
                        v.data.nodes = v.data.dataConverted.data.nodes;
                        if (v.data.nodes.length === 0) {
                            message = "Your data contains an empty nodes array.";
                            v.tools.logError(message);
                            v.data.nodes = [{
                                "ID": "1",
                                "LABEL": "ERROR: " + message,
                                "COLORVALUE": "1",
                                "SIZEVALUE": "1"
                            }];
                        }
                    } else {
                        message = "Your data contains no nodes.";
                        v.tools.logError(message);
                        v.data.nodes = [{
                            "ID": "1",
                            "LABEL": "ERROR: " + message,
                            "COLORVALUE": "1",
                            "SIZEVALUE": "1"
                        }];
                    }
                    if (v.data.dataConverted.data.hasOwnProperty("links") && v.data.dataConverted.data.links !== null) {
                        v.data.links = v.data.dataConverted.data.links;
                    } else {
                        v.data.links = [];
                    }
                } else {
                    message = "Missing root element named data.";
                    v.tools.logError(message);
                    v.data = {
                        "nodes": [{
                            "ID": "1",
                            "LABEL": "ERROR: " + message,
                            "COLORVALUE": "1",
                            "SIZEVALUE": "1"
                        }],
                        "links": []
                    };
                }
            } else {
                message = "Unable to parse your data - please consult the API reference for possible data formats.";
                v.tools.logError(message);
                v.data = {
                    "nodes": [{
                        "ID": "1",
                        "LABEL": "ERROR: " + message,
                        "COLORVALUE": "1",
                        "SIZEVALUE": "1"
                    }],
                    "links": []
                };
            }

            // switch links to point to node objects instead of id's (needed for force layout) and calculate attributes
            v.data.idLookup = []; // helper array to lookup node objects by id's
            v.data.nodes.forEach(function(n) {
                n.SIZEVALUE = parseFloat(n.SIZEVALUE); // convert size to float value
                n.LABELCIRCULAR = v.tools.parseBool(n.LABELCIRCULAR); // convert labelCircular to boolean
                if (n.fixed) {
                    n.fixed = v.tools.parseBool(n.fixed);
                } // convert fixed to boolean
                if (n.x) {
                    n.x = parseFloat(n.x);
                } // convert X position to float value
                if (n.y) {
                    n.y = parseFloat(n.y);
                } // convert Y position to float value
                v.data.idLookup[n.ID] = n; // add object reference to lookup array
            });
            v.data.links.forEach(function(l) {
                l.source = v.data.idLookup[l.FROMID]; // add attribute source as a node reference to the link
                l.target = v.data.idLookup[l.TOID]; // add attribute target as a node reference to the link
            });

            // sort out links with invalid node references
            v.data.links = v.data.links.filter(function(l) {
                return typeof l.source !== "undefined" && typeof l.target !== "undefined";
            });

            // create helper array to lookup if nodes are neighbors
            v.data.neighbors = v.data.links.map(function(l) {
                return l.FROMID + ":" + l.TOID;
            });

            // calculate distinct node colors for the legend
            v.data.distinctNodeColorValues = v.data.nodes
                .map(function(n) {
                    return (n.COLORLABEL ? n.COLORLABEL : "") + ";" + n.COLORVALUE;
                })
                // http://stackoverflow.com/questions/1960473/unique-values-in-an-array
                .filter(function(value, index, self) {
                    return self.indexOf(value) === index;
                })
                .sort(function(a, b) { // http://www.sitepoint.com/sophisticated-sorting-in-javascript/
                    var x = a.toLowerCase(),
                        y = b.toLowerCase();
                    return x < y ? 1 : x > y ? -1 : 0;
                });

            // calculate distinct link colors for the markers
            v.data.distinctLinkColorValues = v.data.links
                .map(function(l) {
                    return l.COLOR;
                })
                // http://stackoverflow.com/questions/28607451/removing-undefined-values-from-array
                // http://stackoverflow.com/questions/1960473/unique-values-in-an-array
                .filter(Boolean)
                .filter(function(value, index, self) {
                    return self.indexOf(value) === index;
                })
                .sort(function(a, b) { // http://www.sitepoint.com/sophisticated-sorting-in-javascript/
                    var x = a.toLowerCase(),
                        y = b.toLowerCase();
                    return x < y ? 1 : x > y ? -1 : 0;
                });

            // apply user provided positions once (new data has priority)
            if (v.conf.positions) {
                if (v.conf.positions.constructor === Array) {
                    v.conf.positions.forEach(function(n) {
                        if (v.data.idLookup[n.ID] !== undefined) {
                            if (!v.data.idLookup[n.ID].fixed) {
                                v.data.idLookup[n.ID].fixed = n.fixed;
                            }
                            if (!v.data.idLookup[n.ID].x) {
                                v.data.idLookup[n.ID].x = v.data.idLookup[n.ID].px = n.x;
                            }
                            if (!v.data.idLookup[n.ID].y) {
                                v.data.idLookup[n.ID].y = v.data.idLookup[n.ID].py = n.y;
                            }
                        }
                    });
                } else {
                    v.tools.logError("Unable to set node positions: positions method parameter must be an array of " +
                        "node positions");
                }
            }
            // apply old positions (new data has priority - if graph was ready, than user provided positions are
            // already present in old positions) - see also graph.positions method
            else if (v.status.graphOldPositions) {
                v.status.graphOldPositions.forEach(function(n) {
                    if (v.data.idLookup[n.ID] !== undefined) {
                        if (!v.data.idLookup[n.ID].fixed) {
                            v.data.idLookup[n.ID].fixed = n.fixed;
                        }
                        if (!v.data.idLookup[n.ID].x) {
                            v.data.idLookup[n.ID].x = v.data.idLookup[n.ID].px = n.x;
                        }
                        if (!v.data.idLookup[n.ID].y) {
                            v.data.idLookup[n.ID].y = v.data.idLookup[n.ID].py = n.y;
                        }
                    }
                });
            }
            // clear positions
            v.conf.positions = null;
            v.status.graphOldPositions = null;

        } //END: if (data)

        // set color and radius function and calculate nodes radius
        v.tools.setColorFunction();
        v.tools.setRadiusFunction();
        v.data.nodes.forEach(function(n) {
            n.radius = v.tools.radius(n.SIZEVALUE);
        });

        // MARKERS
        v.main.markers = v.dom.defs.selectAll("marker.custom")
            .data(v.data.distinctLinkColorValues,
                function(m) {
                    return m;
                }); // distinctLinkColorValues is a simple array, we return the "whole" color value string
        v.main.markers.enter().append("svg:marker")
            .attr("id", function(m) {
                return v.dom.containerId + "_" + m;
            })
            .attr("class", "custom")
            .attr("stroke", "none")
            .attr("fill", function(m) {
                return m;
            })
            .attr("viewBox", "0 0 10 10")
            .attr("refX", 10)
            .attr("refY", 5)
            .attr("markerWidth", 5)
            .attr("markerHeight", 5)
            .attr("orient", "auto")
            .attr("markerUnits", "strokeWidth")
            .append("svg:path")
            .attr("d", "M0,0 L10,5 L0,10");
        v.main.markers.exit().remove();

        // LINKS
        v.main.links = v.dom.graph.selectAll("line.link")
            .data(v.data.links.filter(function(l) {
                    return l.FROMID !== l.TOID;
                }),
                function(l) {
                    return l.FROMID + "_" + l.TOID;
                });
        v.main.links.enter().append("svg:line")
            .attr("class", "link")
            .on("mouseenter", v.tools.onLinkMouseenter)
            .on("mouseleave", v.tools.onLinkMouseleave)
            .on("click", v.tools.onLinkClick);
        v.main.links.exit().remove();
        // update all
        v.main.links
            .style("marker-end", v.tools.getMarkerUrl)
            .classed("dotted", function(l) {
                return (l.STYLE === "dotted");
            })
            .classed("dashed", function(l) {
                return (l.STYLE === "dashed");
            })
            .style("stroke", function(l) {
                return (l.COLOR ? l.COLOR : null);
            });

        // SELFLINKS
        v.main.selfLinks = v.dom.graph.selectAll("path.link")
            .data(v.data.links.filter(function(l) {
                    return l.FROMID === l.TOID && v.conf.showSelfLinks;
                }),
                function(l) {
                    return l.FROMID + "_" + l.TOID;
                });
        v.main.selfLinks.enter().append("svg:path")
            .attr("id", function(l) {
                return v.dom.containerId + "_link_" + l.FROMID + "_" + l.TOID;
            })
            .attr("class", "link")
            .on("mouseenter", v.tools.onLinkMouseenter)
            .on("mouseleave", v.tools.onLinkMouseleave)
            .on("click", v.tools.onLinkClick);
        v.main.selfLinks.exit().remove();
        // update all
        v.main.selfLinks
            .attr("d", function(l) {
                return v.tools.getSelfLinkPath(l);
            })
            .style("marker-end", v.tools.getMarkerUrl)
            .classed("dotted", function(l) {
                return (l.STYLE === "dotted");
            })
            .classed("dashed", function(l) {
                return (l.STYLE === "dashed");
            })
            .style("stroke", function(l) {
                return (l.COLOR ? l.COLOR : null);
            });

        // PATTERN for nodes with image attribute set
        v.main.patterns = v.dom.defs.selectAll("pattern")
            .data(v.data.nodes.filter(function(n) {
                    return (n.IMAGE ? true : false);
                }),
                function(n) {
                    return n.ID;
                });
        v.main.patterns.enter().append("svg:pattern")
            .attr("id", function(n) {
                return v.dom.containerId + "_pattern_" + n.ID;
            })
            .append("svg:image");
        v.main.patterns.exit().remove();
        // update all
        v.main.patterns.each(function() {
            d3.select(this)
                .attr("x", 0)
                .attr("y", 0)
                .attr("height", function(n) {
                    return n.radius * 2;
                })
                .attr("width", function(n) {
                    return n.radius * 2;
                });
            d3.select(this.firstChild)
                .attr("x", 0)
                .attr("y", 0)
                .attr("height", function(n) {
                    return n.radius * 2;
                })
                .attr("width", function(n) {
                    return n.radius * 2;
                })
                .attr("xlink:href", function(n) {
                    return n.IMAGE;
                });
        });

        // NODES
        v.main.nodes = v.dom.graph.selectAll("circle.node")
            .data(v.data.nodes,
                function(n) {
                    return n.ID;
                });
        v.main.nodes.enter().append("svg:circle")
            .attr("class", "node")
            .attr("cx", function(n) {
                if (!n.fixed && !n.x) {
                    n.x = Math.floor((Math.random() * v.tools.getGraphWidth()) + 1);
                    return n.x;
                }
            })
            .attr("cy", function(n) {
                if (!n.fixed && !n.y) {
                    n.y = Math.floor((Math.random() * v.conf.height) + 1);
                    return n.y;
                }
            })
            .on("mouseenter", v.tools.onNodeMouseenter)
            .on("mouseleave", v.tools.onNodeMouseleave)
            .on("click", v.tools.onNodeClick)
            .on("dblclick", v.tools.onNodeDblclick)
            .on("contextmenu", v.tools.onNodeContextmenu);
        v.main.nodes.exit().remove();
        // update all
        v.main.nodes
            .attr("r", function(n) {
                return n.radius;
            })
            .attr("fill", function(n) {
                return (n.IMAGE ? "url(#" + v.dom.containerId + "_pattern_" + n.ID + ")" : v.tools.color(n.COLORVALUE));
            });


        // LABELS

        if (v.conf.showLabels) {

            // normal text labels
            v.main.labels = v.dom.graph.selectAll("text.label")
                .data(v.data.nodes.filter(function(n) {
                        return !n.LABELCIRCULAR && !v.conf.labelsCircular;
                    }),
                    function(n) {
                        return n.ID;
                    });
            v.main.labels.enter().append("svg:text")
                .attr("class", "label");
            v.main.labels.exit().remove();
            // update all
            v.main.labels.text(function(n) {
                return n.LABEL;
            });

            // paths for circular labels
            v.main.labelPaths = v.dom.defs.selectAll("path.label")
                .data(v.data.nodes.filter(function(n) {
                        return n.LABELCIRCULAR || v.conf.labelsCircular;
                    }),
                    function(n) {
                        return n.ID;
                    });
            v.main.labelPaths.enter().append("svg:path")
                .attr("id", function(n) {
                    return v.dom.containerId + "_textPath_" + n.ID;
                })
                .attr("class", "label");
            v.main.labelPaths.exit().remove();
            // update all
            v.main.labelPaths.attr("d", function(n) {
                return v.tools.getLabelPath(n);
            });

            // circular labels
            v.main.labelsCircular = v.dom.graph.selectAll("text.labelCircular")
                .data(v.data.nodes.filter(function(n) {
                        return n.LABELCIRCULAR || v.conf.labelsCircular;
                    }),
                    function(n) {
                        return n.ID;
                    });
            v.main.labelsCircular.enter().append("svg:text")
                .attr("class", "labelCircular")
                .append("svg:textPath")
                .attr("xlink:href", function(n) {
                    return "#" + v.dom.containerId + "_textPath_" + n.ID;
                });
            v.main.labelsCircular.exit().remove();
            // update all
            v.main.labelsCircular.each(function(n) {
                d3.select(this.firstChild).text(n.LABEL);
            });
        } else {
            v.dom.defs.selectAll("path.label").remove();
            v.dom.graph.selectAll("text.label,text.labelCircular").remove();
        }

        // initialize the graph (some options implicit initializes v.main.force, e.g. linkDistance, charge, ...)
        graph
            .debug(v.conf.debug)
            .showBorder(v.conf.showBorder)
            .setDomParentPaddingToZero(v.conf.setDomParentPaddingToZero)
            .useDomParentWidth(v.conf.useDomParentWidth)
            .width(v.conf.width)
            .height(v.conf.height)
            .alignFixedNodesToGrid(v.conf.alignFixedNodesToGrid)
            .dragMode(v.conf.dragMode)
            .pinMode(v.conf.pinMode)
            .lassoMode(v.conf.lassoMode)
            .zoomMode(v.conf.zoomMode)
            .transform(v.conf.transform)
            .autoRefresh(v.conf.autoRefresh)
            .linkDistance(v.conf.linkDistance)
            .wrapLabels(v.conf.wrapLabels)
            .charge(v.conf.charge)
            .chargeDistance(v.conf.chargeDistance)
            .gravity(v.conf.gravity)
            .linkStrength(v.conf.linkStrength)
            .friction(v.conf.friction)
            .theta(v.conf.theta);

        // start visualization
        v.main.force
            .nodes(v.data.nodes)
            .links(v.data.links)
            .start();

        if (v.status.customize) {
            v.tools.createCustomizeWizard();
        } else {
            v.tools.createCustomizeLink();
        }

        v.status.graphReady = true;
        v.status.graphRendering = false;

        v.tools.triggerApexEvent(document.querySelector("#" + v.dom.containerId), "apexafterrefresh");

        return graph;
    };

    /**
     * The `resume` method restarts only the force on your graph without a `render` cycle. This saves CPU time and can be useful if you change only things in your graph which do not need rendering to taking into effect:
     *
     *     example.releaseFixedNodes().resume();
     * @see {@link module:API.start}
     * @see {@link module:API.render}
     * @returns {Object} The graph object for method chaining.
     */
    graph.resume = function() {
        v.main.force.resume();
        v.tools.createCustomizeWizardIfNotRendering();
        return graph;
    };

    /**
     * If true, a class named border is added to the SVG element, if false the class will be removed. The border itself is defined in the delivered CSS - you can overwrite it if the current style does not match your needs. No `render` or `resume` call needed to take into effect:
     *
     *     example.showBorder(false);
     * @param {boolean} [value=true] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.showBorder = function(value) {
        if (!arguments.length) {
            return v.conf.showBorder;
        }
        v.conf.showBorder = value;
        if (v.status.graphStarted) {
            v.dom.svg.classed("border", v.conf.showBorder);
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, a legend for all COLORVALUEs in the node data is rendered in the bottom left corner of the graph. No `render` or `resume` call needed to take into effect:
     *
     *     example.showLegend(false);
     * @param {boolean} [value=true] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.showLegend = function(value) {
        if (!arguments.length) {
            return v.conf.showLegend;
        }
        v.conf.showLegend = value;
        if (v.status.graphStarted) {
            if (v.conf.showLegend) {
                v.tools.removeLegend();
                v.tools.createLegend();
            } else {
                v.tools.removeLegend();
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, then links with the same source and target are rendered along a path around the node bottom. Needs a `render` call to take into effect:
     *
     *     example.showSelfLinks(false).render();
     * @param {boolean} [value=true] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.showSelfLinks = function(value) {
        if (!arguments.length) {
            return v.conf.showSelfLinks;
        }
        v.conf.showSelfLinks = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, you get an marker at the end of a link. Needs a `render` call to take into effect:
     *
     *     example.showLinkDirection(false).render();
     * @param {boolean} [value=true] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.showLinkDirection = function(value) {
        if (!arguments.length) {
            return v.conf.showLinkDirection;
        }
        v.conf.showLinkDirection = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true and you provided in your source data an attribute INFOSTRING, then a tooltip is shown by hovering a node. No `render` or `resume` call needed to take into effect:
     *
     *     example.showTooltips(false);
     * @param {boolean} [value=true] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.showTooltips = function(value) {
        if (!arguments.length) {
            return v.conf.showTooltips;
        }
        v.conf.showTooltips = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The position where tooltips are shown in the graph - can be `node`, `svgTopLeft` or `svgTopRight`. No `render` or `resume` call needed to take into effect:
     *
     *     example.tooltipPosition('node');
     * @param {string} [value=svgTopRight] -  - The new config value.
     * @returns {(string|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.tooltipPosition = function(value) {
        if (!arguments.length) {
            return v.conf.tooltipPosition;
        }
        v.conf.tooltipPosition = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Color scheme can be `color20`, `color20b`, `color20c`, `color10` or `direct`. The first four use the color functions provided by D3, which return up to 20 colors for the given keywords for your data attribute COLORVALUE - this can be a text like a department name or a postal zip code. With the last option you can provide direct css color values in your data like blue or #123456. No `render` or `resume` call needed to take into effect:
     *
     *     example.colorScheme('color10');
     * @param {string} [value=color20] - The new config value.
     * @returns {(string|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.colorScheme = function(value) {
        if (!arguments.length) {
            return v.conf.colorScheme;
        }
        v.conf.colorScheme = value;
        v.tools.setColorFunction();
        if (v.status.graphStarted) {
            v.main.nodes
                .attr("fill", function(n) {
                    return (n.IMAGE ? "url(#" + v.dom.containerId + "_pattern_" + n.ID + ")" :
                        v.tools.color(n.COLORVALUE));
                });
            if (v.conf.showLegend) {
                v.tools.removeLegend();
                v.tools.createLegend();
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true and you provided in your node data an attribute LABEL, then a label is rendered on top of the node. Needs a `render` call to take into effect:
     *
     *     example.showLabels(false).render();
     * @see {@link module:API.wrapLabels}
     * @see {@link module:API.wrappedLabelWidth}
     * @see {@link module:API.wrappedLabelLineHeight}
     * @param {boolean} [value=true] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.showLabels = function(value) {
        if (!arguments.length) {
            return v.conf.showLabels;
        }
        v.conf.showLabels = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true long labels are wrapped. Needs a `render` call to take into effect:
     *
     *     example.wrapLabels(true).render();
     * @see {@link module:API.showLabels}
     * @see {@link module:API.wrappedLabelWidth}
     * @see {@link module:API.wrappedLabelLineHeight}
     * @see {@link module:API.labelsCircular}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.wrapLabels = function(value) {
        if (!arguments.length) {
            return v.conf.wrapLabels;
        }
        v.conf.wrapLabels = value;
        if (v.conf.wrapLabels) {
            v.status.wrapLabelsOnNextTick = true;
        }
        if (v.status.graphStarted) {
            v.main.labels.each(function() { d3.select(this).attr("lines", null) });
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The width of the labels, if option `wrapLabels` is set to true. Needs a `render` call to take into effect:
     *
     *     example.wrappedLabelWidth(40).render();
     * @see {@link module:API.showLabels}
     * @see {@link module:API.wrapLabels}
     * @see {@link module:API.wrappedLabelLineHeight}
     * @see {@link module:API.labelsCircular}
     * @param {number} [value=80] - The new config value.
     * @returns {(number|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.wrappedLabelWidth = function(value) {
        if (!arguments.length) {
            return v.conf.wrappedLabelWidth;
        }
        v.conf.wrappedLabelWidth = value;
        if (v.conf.wrapLabels && v.main.labels) {
            v.main.labels.each(function() { d3.select(this).attr("lines", null) });
            v.status.wrapLabelsOnNextTick = true;
        }
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The line height of labels in `em`, if option `wrapLabels` is set to true. Needs a `render` call to take into effect:
     *
     *     example.wrappedLabelLineHeight(1.5).render();
     * @see {@link module:API.showLabels}
     * @see {@link module:API.wrapLabels}
     * @see {@link module:API.wrappedLabelWidth}
     * @see {@link module:API.labelsCircular}
     * @param {number} [value=1.2] - The new config value.
     * @returns {(number|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.wrappedLabelLineHeight = function(value) {
        if (!arguments.length) {
            return v.conf.wrappedLabelLineHeight;
        }
        v.conf.wrappedLabelLineHeight = value;
        if (v.conf.wrapLabels) {
            v.status.wrapLabelsOnNextTick = true;
        }
        if (v.status.graphStarted) {
            v.main.labels.each(function() { d3.select(this).attr("lines", null) });
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, then the labels are rendered along a path around the nodes.
     *
     * You can overwrite this attribute on node level by setting a attribute called LABELCIRCULAR on the node to true or false. As an example you can see this in the online demo on the node named KING.
     *
     * ATTENTION: If you set the LABELCIRCULAR attribute on a specific or all nodes, then the global configuration parameter labelsCircular has no effect on these nodes.
     *
     * Needs a `render` call to take into effect:
     *
     *     example.labelsCircular(true).render();
     * @see {@link module:API.labelDistance}
     * @see {@link module:API.wrapLabels}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.labelsCircular = function(value) {
        if (!arguments.length) {
            return v.conf.labelsCircular;
        }
        v.conf.labelsCircular = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The distance of a label from the nodes outer border. Needs a `render` call to take into effect:
     *
     *     example.labelDistance(18).render();
     * @see {@link module:API.labelsCircular}
     * @see {@link module:API.wrapLabels}
     * @param {number} [value=12] - The new config value.
     * @returns {(number|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.labelDistance = function(value) {
        if (!arguments.length) {
            return v.conf.labelDistance;
        }
        v.conf.labelDistance = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If set to true the labels are aligned with a simulated annealing function to prevent overlapping when the graph is cooled down (correctly on the force end event and only on labels, who are not circular). Needs a `resume` call to take into effect:
     *
     *     example.preventLabelOverlappingOnForceEnd(true).render();
     * @see {@link module:API.labelPlacementIterations}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.preventLabelOverlappingOnForceEnd = function(value) {
        if (!arguments.length) {
            return v.conf.preventLabelOverlappingOnForceEnd;
        }
        v.conf.preventLabelOverlappingOnForceEnd = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The number of iterations for the preventLabelOverlappingOnForceEnd option - default is 250 - as higher the number, as higher the quality of the result. For details refer to the [description of the simulated annealing function of the author Evan Wang](https://github.com/tinker10/D3-Labeler). Needs a `resume` call to take into effect:
     *
     *     example.preventLabelOverlappingOnForceEnd(true).resume();
     * @see {@link module:API.labelPlacementIterations}
     * @param {number} [value=250] - The new config value.
     * @returns {(number|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.labelPlacementIterations = function(value) {
        if (!arguments.length) {
            return v.conf.labelPlacementIterations;
        }
        v.conf.labelPlacementIterations = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, the nodes are draggable. No `render` or `resume` call needed to take into effect:
     *
     *     example.dragMode(false);
     * @see {@link module:API.pinMode}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.dragMode = function(value) {
        if (!arguments.length) {
            return v.conf.dragMode;
        }
        v.conf.dragMode = value;
        if (v.status.graphStarted) {
            if (v.conf.dragMode) {
                v.main.nodes.call(v.main.drag);
            } else {
                // http://stackoverflow.com/questions/13136355/d3-js-remove-force-drag-from-a-selection
                v.main.nodes.on("mousedown.drag", null);
                v.main.nodes.on("touchstart.drag", null);
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, the nodes are fixed (pinned) at the end of a drag event. No `render` or `resume` call needed to take into effect:
     *
     *     example.pinMode(true);
     * @see {@link module:API.releaseFixedNodes}
     * @see {@link module:API.dragMode}
     * @param {boolean} [value=true] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.pinMode = function(value) {
        if (!arguments.length) {
            return v.conf.pinMode;
        }
        v.conf.pinMode = value;
        if (v.status.graphStarted) {
            if (v.conf.pinMode) {
                v.main.drag.on("dragstart", function(n) {
                    d3.select(this).classed("fixed", n.fixed = 1);
                });
            } else {
                v.main.drag.on("dragstart", null);
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, you can select miltiple nodes with a lasso - think of a graphical multiselect :-). No `render` or `resume` call needed to take into effect:
     *
     *     example.lassoMode(true);
     * @see {@link module:API.zoomMode}
     * @param {boolean} [value=true] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.lassoMode = function(value) {
        if (!arguments.length) {
            return v.conf.lassoMode;
        }
        v.conf.lassoMode = value;
        if (v.status.graphStarted) {
            if (v.conf.lassoMode) {
                v.dom.graphOverlay.call(v.main.lasso);
                v.main.lasso.items(v.main.nodes);
                v.main.lasso.on("start", function() {
                    v.main.lasso.items().classed("selected", false);
                    v.tools.onLassoStart(v.main.lasso.items());
                });
                v.main.lasso.on("draw", function() {
                    v.main.lasso.items().filter(function(d) {
                            return d.possible === true;
                        })
                        .classed("selected", true);
                    v.main.lasso.items().filter(function(d) {
                            return d.possible === false;
                        })
                        .classed("selected", false);
                });
                v.main.lasso.on("end", function() {
                    v.main.lasso.items().filter(function(d) {
                            return d.selected === true;
                        })
                        .classed("selected", true);
                    v.main.lasso.items().filter(function(d) {
                            return d.selected === false;
                        })
                        .classed("selected", false);
                    v.tools.onLassoEnd(v.main.lasso.items());
                });
                // save lasso event for use in event proxy
                v.events.mousedownLasso = v.dom.graphOverlay.on("mousedown.drag");
                v.events.touchstartLasso = v.dom.graphOverlay.on("touchstart.drag");
                //v.events.touchmoveDrag = v.dom.graphOverlay.on("touchmove.drag");
                //v.events.touchendDrag = v.dom.graphOverlay.on("touchend.drag");

                // register event proxy for relevant lasso events who conflict with force functions -> see also
                // v.tools.lassoEventProxy
                v.dom.graphOverlay.on("mousedown.drag", v.tools.lassoEventProxy(v.events.mousedownLasso));
                v.dom.graphOverlay.on("touchstart.drag", v.tools.lassoEventProxy(v.events.touchstartLasso));
                //v.dom.graphOverlay.on("touchmove.drag", v.tools.lassoEventProxy(v.events.touchmoveDrag));
                //v.dom.graphOverlay.on("touchend.drag", v.tools.lassoEventProxy(v.events.touchendDrag));
            } else {
                v.dom.graphOverlay.on(".drag", null);
                v.main.nodes.classed("selected", false);
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, you can zoom and pan the graph.
     *
     * ATTENTION: When zoomMode is set to true then the lassoMode is only working with the pressed alt or shift key.
     *
     * KNOWN BUG: In iOS it is after the first zoom event no more possible to drag a node - instead the whole graph is moved - this is, because iOS Safari provide a wrong event.target.tagName. Also a problem: your are not able to press the alt or shift key - if you want to use lasso and zoom together on a touch device, you have to provide a workaround. One possible way is to provide a button, which turns zoom mode on and off with the API zoomMode method - then the user has the choice between these two modes - not comfortable, but working.
     *
     * No `render` or `resume` call needed to take into effect:
     *
     *     example.zoomMode(true);
     * @see {@link module:API.zoom}
     * @see {@link module:API.zoomSmooth}
     * @see {@link module:API.transform}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.zoomMode = function(value) {
        if (!arguments.length) {
            return v.conf.zoomMode;
        }
        v.conf.zoomMode = value;
        if (v.status.graphStarted) {
            if (v.conf.zoomMode) {
                v.main.zoom.scaleExtent([v.conf.minZoomFactor, v.conf.maxZoomFactor])
                    .size([v.tools.getGraphWidth(), v.conf.height])
                    .on("zoom", v.main.zoomed);
                v.dom.graphOverlay.call(v.main.zoom);
                // save zoom events for use in event proxy
                v.events.dblclickZoom = v.dom.graphOverlay.on("dblclick.zoom");
                v.events.mousedownZoom = v.dom.graphOverlay.on("mousedown.zoom");
                v.events.touchstartZoom = v.dom.graphOverlay.on("touchstart.zoom");
                //v.events.touchmoveZoom = v.dom.graphOverlay.on("touchmove.zoom");
                //v.events.touchendZoom = v.dom.graphOverlay.on("touchend.zoom");

                // register event proxy for relevant zoom events who conflicts with force functions -> see also
                // v.tools.zoomEventProxy
                v.dom.graphOverlay.on("dblclick.zoom", v.tools.zoomEventProxy(v.events.dblclickZoom));
                v.dom.graphOverlay.on("mousedown.zoom", v.tools.zoomEventProxy(v.events.mousedownZoom));
                v.dom.graphOverlay.on("touchstart.zoom", v.tools.zoomEventProxy(v.events.touchstartZoom));
                //v.dom.graphOverlay.on("touchmove.zoom", v.tools.zoomEventProxy(v.events.touchmoveZoom));
                //v.dom.graphOverlay.on("touchend.zoom", v.tools.zoomEventProxy(v.events.touchendZoom));

                // transform graph, if conf is not default
                if (JSON.stringify(v.conf.transform) !== JSON.stringify(v.confDefaults.transform)) {
                    v.dom.graph.attr("transform", "translate(" + v.main.zoom.translate() + ")scale(" +
                        v.main.zoom.scale() + ")");
                    v.tools.writeConfObjectIntoWizard();
                }
            } else {
                // http://stackoverflow.com/questions/22302919/
                // unregister-zoom-listener-and-restore-scroll-ability-in-d3-js/22303160?noredirect=1#22303160
                v.dom.graphOverlay.on(".zoom", null);
                v.main.zoom.translate([0, 0]);
                v.main.zoom.scale(1);
                v.conf.transform = {
                    "translate": [0, 0],
                    "scale": 1
                };
                v.dom.graph.attr("transform", "translate(0,0)scale(1)");
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * No `render` or `resume` call needed to take into effect::
     *
     *     example.minZoomFactor(0.1);
     * @see {@link module:API.maxZoomFactor}
     * @param {number} [value=0.2] - The new config value.
     * @returns {(number|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.minZoomFactor = function(value) {
        if (!arguments.length) {
            return v.conf.minZoomFactor;
        }
        v.conf.minZoomFactor = value;
        if (v.status.graphReady) {
            graph.zoomMode(v.conf.zoomMode);
        }
        return graph;
    };

    /**
     * No `render` or `resume` call needed to take into effect::
     *
     *     example.maxZoomFactor(10);
     * @see {@link module:API.minZoomFactor}
     * @param {number} [value=5] - The new config value.
     * @returns {(number|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.maxZoomFactor = function(value) {
        if (!arguments.length) {
            return v.conf.maxZoomFactor;
        }
        v.conf.maxZoomFactor = value;
        if (v.status.graphReady) {
            graph.zoomMode(v.conf.zoomMode);
        }
        return graph;
    };

    /**
     * If the graph option `zoomMode` is set to true, then the graph is centered to the given position and scaled to the calculated scale factor (effective graph with / viewportWidth). The reason to have a viewportWidth instead of a scale factor is, that you can rely on given data like the coordinates and radius of a node without calculating the scale factor by yourself - you define your desired viewport width and the zoom method is calculating the neccesary scale factor for this viewport width. If the calculated scale factor is less then or greater then the configured minimum and maximum scale factors, then these configured scale factors are used. The reason for this a good user experience, since the graph would be otherwise falling back on these scale factors when the user is scaling the graph by mouse or touch events. No `render` or `resume` call needed to take into effect:
     *
     *     var node = example.nodeDataById('9999');
     *     example.zoom(node.x, node.y, node.radius * 6);
     * @see {@link module:API.zoomMode}
     * @see {@link module:API.zoomSmooth}
     * @see {@link module:API.minZoomFactor}
     * @see {@link module:API.maxZoomFactor}
     * @see {@link module:API.transform}
     * @param {number} [centerX=graph width / 2] - The horizontal center position.
     * @param {number} [centerY=graph height / 2] - The vertical center position.
     * @param {number} [viewportWidth=graph width] - The desired viewport width.
     * @returns {Object} The graph object for method chaining.
     */
    graph.zoom = function(centerX, centerY, viewportWidth) {
        graph.zoomSmooth(centerX, centerY, viewportWidth, 0);
        return graph;
    };

    /**
     * This method does the same as the zoom method - the difference is, that the zoom is animated in a nice way and there is a optional fourth parameter for the duration of the transition, which defaults to 1500ms. No `render` or `resume` call needed to take into effect:
     *
     *     var node = example.nodeDataById('8888');
     *     example.zoomSmooth(node.x, node.y, node.radius * 6); // default duration of 1500ms
     *
     *     var node = example.nodeDataById('9999');
     *     example.zoomSmooth(node.x, node.y, node.radius * 6, 3000); // duration of 3000ms
     * @see {@link module:API.zoomMode}
     * @see {@link module:API.zoom}
     * @see {@link module:API.minZoomFactor}
     * @see {@link module:API.maxZoomFactor}
     * @see {@link module:API.transform}
     * @param {number} [centerX=graph width / 2] - The horizontal center position.
     * @param {number} [centerY=graph height / 2] - The vertical center position.
     * @param {number} [viewportWidth=graph width] - The desired viewport width.
     * @param {number} [duration=1500] - the duration of the transition
     * @returns {Object} The graph object for method chaining.
     */
    graph.zoomSmooth = function(centerX, centerY, viewportWidth, duration) {
        // http://bl.ocks.org/linssen/7352810
        var x, y, scale;
        var width = v.tools.getGraphWidth(); // could be different then configured (responsive)
        centerX = (isNaN(centerX) ? width / 2 : parseInt(centerX));
        centerY = (isNaN(centerY) ? v.conf.height / 2 : parseInt(centerY));
        viewportWidth = (isNaN(viewportWidth) ? width : parseInt(viewportWidth));
        duration = (isNaN(duration) ? 1500 : parseInt(duration));
        scale = width / viewportWidth;
        x = width / 2 - centerX * scale;
        y = v.conf.height / 2 - centerY * scale;
        v.main.interpolateZoom([x, y], scale, duration);
        return graph;
    };

    /**
     * Behaves like a normal getter/setter (the `zoom` and `zoomSmooth` methods implements only setters) and can be used in the conf object to initialize the graph with different translate values/scale factors than [0,0]/1. Works only, if the `zoomMode` is set to true. The current transform value(an object) is rendered in the customization wizard conf object text area like all other options when the current value is different then the default value. No `render` or `resume` call needed to take into effect:
     *
     *     //example.zoomMode(true);
     *     example.transform({"translate":[100,100],"scale":0.5});
     * @see {@link module:API.zoomMode}
     * @see {@link module:API.zoom}
     * @see {@link module:API.zoomSmooth}
     * @param {Object} [transform={“translate”:[0,0],“scale”:1}] - The new config value.
     * @returns {Object} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.transform = function(transform) {
        if (!arguments.length) {
            return {
                "translate": v.main.zoom.translate(),
                "scale": v.main.zoom.scale()
            };
        } else {
            v.main.interpolateZoom(transform.translate, transform.scale, 0);
        }
        return graph;
    };

    /**
     * Helper/Command method - automatically zoom, so that the whole graph is visible and optimal sized. No `render` or `resume` call needed to take into effect:
     *
     *     example.zoomToFit();
     * @see {@link module:API.zoomMode}
     * @see {@link module:API.zoomSmooth}
     * @see {@link module:API.minZoomFactor}
     * @see {@link module:API.maxZoomFactor}
     * @see {@link module:API.transform}
     * @see {@link module:API.zoomToFitOnForceEnd}
     * @param {number} [duration=500] - The transition duration in milliseconds.
     * @returns {Object} The graph object for method chaining.
     */
    graph.zoomToFit = function(duration) {
        var svg = {},
            graph_, padding = 10,
            x, y, scale;
        duration = (isNaN(duration) ? 500 : parseInt(duration));
        svg.width = v.tools.getGraphWidth();
        svg.height = v.conf.height;
        graph_ = v.dom.graph.node().getBBox();
        scale = Math.min((svg.height - 2 * padding) / graph_.height,
            (svg.width - 2 * padding) / graph_.width);
        x = (svg.width - graph_.width * scale) / 2 - graph_.x * scale;
        y = (svg.height - graph_.height * scale) / 2 - graph_.y * scale;
        v.main.interpolateZoom([x, y], scale, duration);
        return graph;
    };

    /**
     * Automatically zoom at force end, so that the whole graph is visible and optimal sized. Needs a `resume` call to take into effect or must be set at initialization (before the graph starts). If enabled it fires at every force end event. If you only want to resize your graph once than have a look at the command/helper method `zoomToFit`:
     *
     *     //running graph: change config
     *     example.zoomToFitOnForceEnd(true).resume();
     *     //alternative way without a resume call
     *     example.zoomToFitOnForceEnd(true).zoomToFit();
     *
     *     //running graph: resize only once
     *     example.zoomToFit();
     * @see {@link module:API.zoomMode}
     * @see {@link module:API.zoomSmooth}
     * @see {@link module:API.minZoomFactor}
     * @see {@link module:API.maxZoomFactor}
     * @see {@link module:API.transform}
     * @see {@link module:API.zoomToFit}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.zoomToFitOnForceEnd = function(value) {
        if (!arguments.length) {
            return v.conf.zoomToFitOnForceEnd;
        }
        v.conf.zoomToFitOnForceEnd = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, a loading indicator is shown when used as a APEX plugin during the AJAX calls. If you want to show the loading indicator in a standalone implementation you can show and hide the loading indicator directly with the API method `showLoadingIndicator`:
     *
     *     example.showLoadingIndicatorOnAjaxCall(false);
     * @see {@link module:API.showLoadingIndicator}
     * @param {boolean} [value=true] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.showLoadingIndicatorOnAjaxCall = function(value) {
        if (!arguments.length) {
            return v.conf.showLoadingIndicatorOnAjaxCall;
        }
        v.conf.showLoadingIndicatorOnAjaxCall = value;
        return graph;
    };

    /**
     * Helper method to directly show or hide a loading indicator. The APEX plugin do this implicitly on AJAX calls when the option `showLoadingIndicatorOnAjaxCall` is set to true. No `render` or `resume` call needed to take into effect:
     *
     *     // Show:
     *     example.showLoadingIndicator(true);
     *
     *     // Hide:
     *     example.showLoadingIndicator(false);
     * @see {@link module:API.showLoadingIndicatorOnAjaxCall}
     * @param {boolean} - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.showLoadingIndicator = function(value) {
        if (v.tools.parseBool(value)) {
            v.dom.loading.style("display", "block");
        } else {
            v.dom.loading.style("display", "none");
        }
        return graph;
    };

    /**
     * If true, fixed nodes are aligned to the nearest grid position on the drag end event. You can pin nodes, when `pinMode` is set to true or by delivering nodes with the attribute “fixed” set to true and “x” and “y” attributes for the position. If you have already fixed nodes on your graph you can also set this attribute at runtime and resume the force. Needs a `resume` call to take into effect:
     *
     *     example.alignFixedNodesToGrid(true).resume();
     * @see {@link module:API.gridSize}
     * @see {@link module:API.pinMode}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.alignFixedNodesToGrid = function(value) {
        if (!arguments.length) {
            return v.conf.alignFixedNodesToGrid;
        }
        v.conf.alignFixedNodesToGrid = value;
        if (v.status.graphStarted) {
            // align fixed nodes to grid
            if (v.conf.alignFixedNodesToGrid) {
                // NO aligning on the very first start: this would overwrite user defined positions
                if (v.status.graphReady) {
                    v.main.nodes.each(function(n) {
                        if (n.fixed) {
                            n.x = n.px = v.tools.getNearestGridPosition(n.x, v.conf.width);
                            n.y = n.py = v.tools.getNearestGridPosition(n.y, v.conf.height);
                        }
                    });
                }
                v.main.drag.on("dragend", function(n) {
                    n.x = n.px = v.tools.getNearestGridPosition(n.x, v.conf.width);
                    n.y = n.py = v.tools.getNearestGridPosition(n.y, v.conf.height);
                });
            } else {
                v.main.drag.on("dragend", null);
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The grid size of the virtual grid for the option `alignFixedNodesToGrid`. Needs a `resume` call to take into effect:
     *
     *     example.gridSize(100).alignFixedNodesToGrid(true).resume();
     * @see {@link module:API.alignFixedNodesToGrid}
     * @see {@link module:API.pinMode}
     * @param {number} [value=50] - The new config value.
     * @returns {(number|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.gridSize = function(value) {
        if (!arguments.length) {
            return v.conf.gridSize;
        }
        v.conf.gridSize = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Command method (has no get or set function). Moves all fixed nodes in the provided direction. Needs a `resume` call to take into effect:
     *
     *     example.moveFixedNodes(10,-5).resume();
     *
     * The example adds 10 to x position and -5 to y position to all fixed nodes. ATTENTION: If alignFixedNodesToGrid is set to true this can have unexpected behavior - you must then provide values greater then gridSize halved to see any changes on your graph, otherwise the positions are falling back to the nearest (current) grid position.
     * @see {@link module:API.pinMode}
     * @see {@link module:API.alignFixedNodesToGrid}
     * @param {number} [x=0] - x value - positive or negative
     * @param {number} [y=0] - y value - positive or negative
     * @returns {Object} The graph object for method chaining.
     */
    graph.moveFixedNodes = function(x, y) {
        if (v.status.graphStarted) {
            if (!x) {
                x = 0;
            }
            if (!y) {
                y = 0;
            }
            if (x !== 0 || y !== 0) {
                v.main.nodes.each(function(n) {
                    if (n.fixed) {
                        n.x = n.px = (v.conf.alignFixedNodesToGrid ?
                            v.tools.getNearestGridPosition(n.x + x, v.conf.width) : n.x + x);
                        n.y = n.py = (v.conf.alignFixedNodesToGrid ?
                            v.tools.getNearestGridPosition(n.y + y, v.conf.width) : n.y + y);
                    }
                });
            }
        }
        return graph;
    };

    /**
     * Command method (has no get or set function and expects no parameter): Release all fixed (pinned) nodes. Needs a `resume` call to take into effect:
     *
     *     example.releaseFixedNodes().resume();
     * @see {@link module:API.pinMode}
     * @see {@link module:API.alignFixedNodesToGrid}
     * @returns {Object} The graph object for method chaining.
     */
    graph.releaseFixedNodes = function() {
        if (v.status.graphStarted) {
            v.main.nodes.each(function(n) {
                n.fixed = 0;
            });
        }
        return graph;
    };

    /**
     * Can be “none”, “click”, “dblclick” and “contextmenu” and defines, which event will release a node. This releasing of a node is sometimes a bit unstable (not on the code side, but on the visualizing side) and depends on the next tick event. You have to play around with this. If you want only release all nodes you can simply call the releaseFixedNodes method and resume the graph. No `render` or `resume` call needed to take into effect:
     *
     *     example.nodeEventToStopPinMode("contextmenu");
     * @see {@link module:API.releaseFixedNodes}
     * @param {string} [value="contextmenu"] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.nodeEventToStopPinMode = function(value) {
        if (!arguments.length) {
            return v.conf.nodeEventToStopPinMode;
        }
        v.conf.nodeEventToStopPinMode = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, the context menu default browser action on the nodes are prevented. This could be useful, if you want to implement an own context menu for the nodes. xxx:
     *
     *     example.onNodeContextmenuPreventDefault(true);
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.onNodeContextmenuPreventDefault = function(value) {
        if (!arguments.length) {
            return v.conf.onNodeContextmenuPreventDefault;
        }
        v.conf.onNodeContextmenuPreventDefault = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Can be “none”, “click”, “dblclick” or “contextmenu”. Works only for nodes with a non empty LINK attribute. No `render` or `resume` call needed to take into effect:
     *
     *     example.nodeEventToOpenLink("click");
     * @param {string} [value="dblclick"] - The new config value.
     * @returns {(string|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.nodeEventToOpenLink = function(value) {
        if (!arguments.length) {
            return v.conf.nodeEventToOpenLink;
        }
        v.conf.nodeEventToOpenLink = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * This text is used as the link target, when a node has a LINK attribute.
     *
     * There are three special keywords: “none”, “nodeID” and “domContainerID”. If you use “none”, the link is opened in the same window/tab where your graph is currently shown. If you use “nodeID”, the ID of the currently clicked node is used as the target attribute, this means - you get one window/tab for each node in your graph - when you click a second time on the same node, the window/tab is reused. The same with the keyword “domContainerID” - you get one window/tab for each graph on your page - when you click a second time on the same node, the window/tab is reused.
     *
     * Anything else is not interpreted - your given text is simply used as the target attribute of the link. This is also the case for the second option in the customize wizard called “_blank”. If you use this, then each click on a node opens in a new window/tab. You are not restricted to use only the predefined select options. It is up to you to overwrite the value in your configuration object. As an example: If you want to have always the same window/tab for each click on a node, then simply provide a text here, that fit your needs e.g. “myOwnWindowName”.
     *
     *     example.nodeLinkTarget("myOwnWindowName");
     * @see {@link module:API.nodeEventToOpenLink}
     * @param {string} [value="_blank"] - The new config value.
     * @returns {(string|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.nodeLinkTarget = function(value) {
        if (!arguments.length) {
            return v.conf.nodeLinkTarget;
        }
        v.conf.nodeLinkTarget = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, the graph is refreshed automatically. This makes only sense when running as APEX plugin - here you have the SQL queries for loading new data with AJAX. If you run your code standalone, you have to provide new data as a parameter in the start or render method and therefore you have to use your own auto refresh logic. No `render` or `resume` call needed to take into effect:
     *
     *     example.autoRefresh(true);
     * @see {@link module:API.refreshInterval}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.autoRefresh = function(value) {
        if (!arguments.length) {
            return v.conf.autoRefresh;
        }
        v.conf.autoRefresh = value;
        if (v.status.graphStarted) {
            if (v.conf.autoRefresh && v.conf.refreshInterval && !v.conf.interval) {
                v.conf.interval = window.setInterval(function() {
                    graph.start();
                }, v.conf.refreshInterval);
                v.tools.log("Auto refresh started with an interval of " + v.conf.refreshInterval + " milliseconds.");
            } else if (!v.conf.autoRefresh && v.conf.interval) {
                clearInterval(v.conf.interval);
                v.conf.interval = null;
                v.tools.log("Auto refresh stopped.");
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The refresh interval in milliseconds. No `render` or `resume` call needed to take into effect, but after changing the interval value you have to stop a current activated auto refresh and start it again to take the new value into effect:
     *
     *     // only set the value and start auto refresh
     *     example.refreshInterval(4000).autoRefresh(true);
     *
     *     // restart running auto refresh
     *     example.refreshInterval(2000).autoRefresh(false).autoRefresh(true);
     * @see {@link module:API.autoRefresh}
     * @param {number} [value=5000] - The new config value.
     * @returns {(number|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.refreshInterval = function(value) {
        if (!arguments.length) {
            return v.conf.refreshInterval;
        }
        v.conf.refreshInterval = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, the width of the chart(SVG element) is aligned to its DOM parent element. Needs a `render` call to take into effect:
     *
     *     example.useDomParentWidth(true).render();
     * @see {@link module:API.setDomParentPaddingToZero}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.useDomParentWidth = function(value) {
        if (!arguments.length) {
            return v.conf.useDomParentWidth;
        }
        v.conf.useDomParentWidth = value;
        if (v.status.graphStarted) {
            if (v.conf.useDomParentWidth) {
                v.dom.containerWidth = v.tools.getSvgParentInnerWidth();
                d3.select(window).on("resize", function() {
                    var oldWidth = v.dom.containerWidth;
                    var newWidth = v.tools.getSvgParentInnerWidth();
                    if (oldWidth !== newWidth) {
                        v.dom.containerWidth = newWidth;
                        graph.width(v.conf.width).resume();
                    }
                });
            } else {
                d3.select(window).on("resize", null);
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * If true, the parent DOM element of the graph gets the style { padding: 0px; }. If set to false, this style is removed from the DOM parent of the graph. No `render` or `resume` call needed to take into effect:
     *
     *     example.setDomParentPaddingToZero(true);
     * @see {@link module:API.useDomParentWidth}
     * @param {boolean} [value=false] - The new config value.
     * @returns {(boolean|Object)} The current config value if no parameter is given or the graph object for method chaining.
     */
    graph.setDomParentPaddingToZero = function(value) {
        if (!arguments.length) {
            return v.conf.setDomParentPaddingToZero;
        }
        v.conf.setDomParentPaddingToZero = value;
        if (v.status.graphStarted) {
            if (v.conf.setDomParentPaddingToZero) {
                v.dom.svgParent.style("padding", "0");
            } else {
                v.dom.svgParent.style("padding", null);
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Returns the current with of the graphs DOM parent. This method expects no parameter and terminates the method chain.
     *
     * If the option useDomParentWidth is set to true, then this is the effective width of the graph - independent of the configured width.
     *
     *     example.domParentWidth();
     * @returns {number} The current DOM parent width.
     */
    graph.domParentWidth = function() {
        return v.dom.containerWidth || v.tools.getSvgParentInnerWidth();
    };

    /**
     * The width of the chart. Needs a `resume` call to take into effect:
     *
     *     example.width(800).resume();
     * @see {@link module:API.height}
     * @param {number} [value=500] - The new chart width value.
     * @returns {(number|Object)} The current chart width value if no parameter is given or the graph object for method chaining.
     */
    graph.width = function(value) {
        if (!arguments.length) {
            return v.conf.width;
        }
        v.conf.width = value;
        if (v.status.graphStarted) {
            v.dom.svg.attr("width", v.tools.getGraphWidth());
            v.dom.graphOverlaySizeHelper.attr("width", v.tools.getGraphWidth());
            v.dom.loadingRect.attr("width", v.tools.getGraphWidth());
            v.dom.loadingText.attr("x", v.tools.getGraphWidth() / 2);
            v.main.force.size([v.tools.getGraphWidth(), v.conf.height]);
            if (v.conf.zoomMode) {
                v.main.zoom.size([v.tools.getGraphWidth(), v.conf.height]);
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The height of the chart. Needs a `resume` call to take into effect:
     *
     *     example.height(600).resume();
     * @see {@link module:API.width}
     * @param {number} [value=500] - The new chart height value.
     * @returns {(number|Object)} The current chart height value if no parameter is given or the graph object for method chaining.
     */
    graph.height = function(value) {
        if (!arguments.length) {
            return v.conf.height;
        }
        v.conf.height = value;
        if (v.status.graphStarted) {
            v.dom.svg.attr("height", v.conf.height);
            v.dom.graphOverlaySizeHelper.attr("height", v.conf.height);
            v.dom.loadingRect.attr("height", v.conf.height);
            v.dom.loadingText.attr("y", v.conf.height / 2);
            v.main.force.size([v.tools.getGraphWidth(), v.conf.height]);
            if (v.conf.showLegend) {
                v.tools.removeLegend();
                v.tools.createLegend();
            }
            if (v.conf.zoomMode) {
                v.main.zoom.size([v.tools.getGraphWidth(), v.conf.height]);
            }
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The minimum node radius. Each node radius is calculated by its SIZEVALUE attribute in a range between the minimum and the maximum node radius. Needs a `render` call to take into effect:
     *
     *     example.minNodeRadius(2).render();
     * @see {@link module:API.maxNodeRadius}
     * @param {number} [value=6] - The new min node radius value.
     * @returns {(number|Object)} The current min node radius value if no parameter is given or the graph object for method chaining.
     */
    graph.minNodeRadius = function(value) {
        if (!arguments.length) {
            return v.conf.minNodeRadius;
        }
        v.conf.minNodeRadius = value;
        if (v.status.graphReady) {
            v.tools.setRadiusFunction();
            v.main.nodes.each(function(n) {
                n.radius = v.tools.radius(n.SIZEVALUE);
            });
            v.main.nodes.attr("r", function(n) {
                return n.radius;
            });
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The maximum node radius. Each node radius is calculated by its SIZEVALUE attribute in a range between the minimum and the maximum node radius. Needs a `render` call to take into effect:
     *
     *     example.maxNodeRadius(24).render();
     * @see {@link module:API.minNodeRadius}
     * @param {number} [value=18] - The new max node radius value.
     * @returns {(number|Object)} The current max node radius value if no parameter is given or the graph object for method chaining.
     */
    graph.maxNodeRadius = function(value) {
        if (!arguments.length) {
            return v.conf.maxNodeRadius;
        }
        v.conf.maxNodeRadius = value;
        if (v.status.graphReady) {
            v.tools.setRadiusFunction();
            v.main.nodes.each(function(n) {
                n.radius = v.tools.radius(n.SIZEVALUE);
            });
            v.main.nodes.attr("r", function(n) {
                return n.radius;
            });
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The distance of the self link path around a node. Needs a `render` call to take into effect:
     *
     *     example.selfLinkDistance(25).render();
     * @see {@link module:API.linkDistance}
     * @param {number} [value=20] - The new self link distance value.
     * @returns {(number|Object)} The current self link distance value if no parameter is given or the graph object for method chaining.
     */
    graph.selfLinkDistance = function(value) {
        if (!arguments.length) {
            return v.conf.selfLinkDistance;
        }
        v.conf.selfLinkDistance = value;
        if (v.status.graphStarted) {
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * The distance between nodes centers. Needs a `render` call to take into effect:
     *
     *     example.linkDistance(60).render();
     * @see {@link module:API.selfLinkDistance}
     * @param {number} [value=80] - The new link distance value.
     * @returns {(number|Object)} The current link distance value if no parameter is given or the graph object for method chaining.
     */
    graph.linkDistance = function(value) {
        if (!arguments.length) {
            return v.conf.linkDistance;
        }
        v.conf.linkDistance = value;
        if (v.status.graphStarted) {
            v.main.force.linkDistance(v.conf.linkDistance);
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Gets or sets the charge strength to the specified value. For more informations have a look at the [D3 API Reference](https://github.com/d3/d3-3.x-api-reference/blob/master/Force-Layout.md#charge). Needs a `render` call to take into effect:
     *
     *     example.charge(-200).render();
     * @see {@link module:API.chargeDistance}
     * @param {number} [value=-350] - The new charge value.
     * @returns {(number|Object)} The current charge value if no parameter is given or the graph object for method chaining.
     */
    graph.charge = function(value) {
        if (!arguments.length) {
            return v.conf.charge;
        }
        v.conf.charge = value;
        if (v.status.graphStarted) {
            v.main.force.charge(v.conf.charge);
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Gets or sets the maximum distance over which charge forces are applied. For more informations have a look at the [D3 API Reference](https://github.com/d3/d3-3.x-api-reference/blob/master/Force-Layout.md#chargeDistance). This option is not shown in the customize wizard. Needs a `render` call to take into effect:
     *
     *     example.chargeDistance(200).render();
     * @see {@link module:API.charge}
     * @param {number} [value=Infinity] - The new charge distance value.
     * @returns {(number|Object)} The current charge distance value if no parameter is given or the graph object for method chaining.
     */
    graph.chargeDistance = function(value) {
        if (!arguments.length) {
            return v.conf.chargeDistance;
        }
        v.conf.chargeDistance = value;
        if (v.status.graphStarted) {
            v.main.force.chargeDistance(v.conf.chargeDistance);
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Gets or sets the gravitational strength to the specified numerical value. For more informations see the [D3 API Reference](https://github.com/d3/d3-3.x-api-reference/blob/master/Force-Layout.md#gravity). Needs a `render` call to take into effect:
     *
     *     example.gravity(0.3).render();
     * @param {number} [value=0.1] - The new gravity value.
     * @returns {(number|Object)} The current gravity value if no parameter is given or the graph object for method chaining.
     */
    graph.gravity = function(value) {
        if (!arguments.length) {
            return v.conf.gravity;
        }
        v.conf.gravity = value;
        if (v.status.graphStarted) {
            v.main.force.gravity(v.conf.gravity);
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Gets or sets the strength (rigidity) of links to the specified value in the range [0,1]. For more informations see the [D3 API Reference](https://github.com/d3/d3-3.x-api-reference/blob/master/Force-Layout.md#linkStrength). Needs a `render` call to take into effect:
     *
     *     example.linkStrength(0.1).render();
     * @param {number} [value=1] - The new link strength value.
     * @returns {(number|Object)} The current link strength value if no parameter is given or the graph object for method chaining.
     */
    graph.linkStrength = function(value) {
        if (!arguments.length) {
            return v.conf.linkStrength;
        }
        v.conf.linkStrength = value;
        if (v.status.graphStarted) {
            v.main.force.linkStrength(v.conf.linkStrength);
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Gets or sets the friction coefficient to the specified value. For more informations have a look at the [D3 API Reference](https://github.com/d3/d3-3.x-api-reference/blob/master/Force-Layout.md#friction). Needs a `render` call to take into effect:
     *
     *     example.friction(0.4).render();
     * @param {number} [value=0.9] - The new friction value.
     * @returns {(number|Object)} The current friction value if no parameter is given or the graph object for method chaining.
     */
    graph.friction = function(value) {
        if (!arguments.length) {
            return v.conf.friction;
        }
        v.conf.friction = value;
        if (v.status.graphStarted) {
            v.main.force.friction(v.conf.friction);
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Gets or sets the Barnes–Hut approximation criterion to the specified value. For more informations see the [D3 API Reference](https://github.com/d3/d3-3.x-api-reference/blob/master/Force-Layout.md#theta). On smaller graphs with not so many nodes you will likely see no difference when you change this value. Needs a `render` call to take into effect:
     *
     *     example.theta(0.1).render();
     * @param {number} [value=0.8] - The new theta value.
     * @returns {(number|Object)} The current theta value if no parameter is given or the graph object for method chaining.
     */
    graph.theta = function(value) {
        if (!arguments.length) {
            return v.conf.theta;
        }
        v.conf.theta = value;
        if (v.status.graphStarted) {
            v.main.force.theta(v.conf.theta);
            v.tools.createCustomizeWizardIfNotRendering();
        }
        return graph;
    };

    /**
     * Gets or sets the current positions of all nodes. This lets you save and load a specific layout or modify the current positions (of fixed nodes - if you have no fixed nodes then the nodes will likely fall back to their previous positions because of the working forces). Works nice together with the `pinMode`. Needs a `resume` call to take into effect:
     *
     *     // get current positions: Array of objects like [{"ID":"7839","x":200,"y":100,"fixed":1},...])
     *     var pos = example.positions();
     *     // set positions
     *     example.positions(pos.map(function(p){ p.x += 10; return p; })).resume();
     *
     *     // all in one ;-)
     *     example.positions( example.positions().map(function(p){ p.x += 10; return p; }) ).resume();
     * @see {@link module:API.pinMode}
     * @param {Object} [positionsArray] - The new positions array.
     * @returns {Object} The current positions array if no parameter is given or the graph object for method chaining.
     */
    graph.positions = function(positionsArray) {
        if (!arguments.length) {
            var positions = [];
            v.data.nodes.forEach(function(n) {
                positions.push({
                    "ID": n.ID,
                    "x": Math.round(n.x),
                    "y": Math.round(n.y),
                    "fixed": (n.fixed ? 1 : 0)
                });
            });
            return positions;
        } else {
            if (v.status.graphReady) {
                if (positionsArray.constructor === Array) {
                    positionsArray.forEach(function(n) {
                        if (v.data.idLookup[n.ID] !== undefined) {
                            v.data.idLookup[n.ID].fixed = v.tools.parseBool(n.fixed);
                            v.data.idLookup[n.ID].x = v.data.idLookup[n.ID].px = n.x;
                            v.data.idLookup[n.ID].y = v.data.idLookup[n.ID].py = n.y;
                        }
                    });
                } else {
                    v.tools.logError("Unable to set node positions: positions method parameter must be an array of " +
                        "node positions");
                }
            } else {
                v.conf.positions = positionsArray; // we do positioning later after start() is called
            }
            return graph;
        }
    };

    /**
     * Gets or sets the function for the link click event.
     *
     * In the first two parameters you get the event and the d3 node data, inside your function you have access to the DOM node with the this keyword:
     *
     *     example.onLinkClickFunction(
     *         function(event, data){
     *           console.log("Link click - event:", event);
     *           console.log("Link click - data:", data);
     *           console.log("Link click - this:", this);
     *         }
     *     );
     *
     * If used as APEX plugin you can also create an APEX dynamic action on the component event “Link Click [D3 - Force Layout]” on your graph region. If you do so, you can access the event and data by executing JavaScript code in this way:
     *
     *     console.log("Link click - event:", this.browserEvent);
     *     console.log("Link click - data:", this.data);
     *
     * Please refer also to the APEX dynamic action documentation and keep in mind, that the data is the same in both ways but the event differs, because APEX provide a jQuery event and the Plugin the D3 original event.
     *
     * Attention: It is not so easy to click a link, because the links are so narrow - if this option is needed I recommend to switch on the zoom mode - with zoom and pan it feels more natural to click links.
     * @param {Object} [eventFunction] - The new function.
     * @returns {Object} The current function if no parameter is given or the graph object for method chaining.
     */
    graph.onLinkClickFunction = function(eventFunction) {
        if (!arguments.length) {
            return v.conf.onLinkClickFunction;
        }
        v.conf.onLinkClickFunction = eventFunction;
        return graph;
    };

    /**
     * Gets or sets the function for the node mouseenter event.
     *
     * In the first two parameters you get the event and the d3 node data, inside your function you have access to the DOM node with the this keyword:
     *
     *     example.onNodeMouseenterFunction(
     *         function(event, data){
     *           console.log("Node mouse enter - event:", event);
     *           console.log("Node mouse enter - data:", data);
     *           console.log("Node mouse enter - this:", this);
     *         }
     *     );
     *
     * If used as APEX plugin you can also create an APEX dynamic action on the component event “Node Mouse Enter [D3 - Force Layout]” on your graph region. If you do so, you can access the event and data by executing JavaScript code in this way:
     *
     *     console.log("Node mouse enter - event:", this.browserEvent);
     *     console.log("Node mouse enter - data:", this.data);
     *
     * Please refer also to the APEX dynamic action documentation and keep in mind, that the data is the same in both ways but the event differs, because APEX provide a jQuery event and the Plugin the D3 original event.
     * @param {Object} [eventFunction] - The new function.
     * @returns {Object} The current function if no parameter is given or the graph object for method chaining.
     */
    graph.onNodeMouseenterFunction = function(eventFunction) {
        if (!arguments.length) {
            return v.conf.onNodeMouseenterFunction;
        }
        v.conf.onNodeMouseenterFunction = eventFunction;
        return graph;
    };

    /**
     * Gets or sets the function for the node mouseleave event.
     *
     * In the first two parameters you get the event and the d3 node data, inside your function you have access to the DOM node with the this keyword:
     *
     *     example.onNodeMouseleaveFunction(
     *         function(event, data){
     *           console.log("Node mouse leave - event:", event);
     *           console.log("Node mouse leave - data:", data);
     *           console.log("Node mouse leave - this:", this);
     *         }
     *     );
     *
     * If used as APEX plugin you can also create an APEX dynamic action on the component event “Node Mouse Leave [D3 - Force Layout]” on your graph region. If you do so, you can access the event and data by executing JavaScript code in this way:
     *
     *     console.log("Node mouse leave - event:", this.browserEvent);
     *     console.log("Node mouse leave - data:", this.data);
     *
     * Please refer also to the APEX dynamic action documentation and keep in mind, that the data is the same in both ways but the event differs, because APEX provide a jQuery event and the Plugin the D3 original event.
     * @param {Object} [eventFunction] - The new function.
     * @returns {Object} The current function if no parameter is given or the graph object for method chaining.
     */
    graph.onNodeMouseleaveFunction = function(value) {
        if (!arguments.length) {
            return v.conf.onNodeMouseleaveFunction;
        }
        v.conf.onNodeMouseleaveFunction = value;
        return graph;
    };

    /**
     * Gets or sets the function for the node click event.
     *
     * In the first two parameters you get the event and the d3 node data, inside your function you have access to the DOM node with the this keyword:
     *
     *     example.onNodeClickFunction(
     *         function(event, data){
     *           console.log("Node click - event:", event);
     *           console.log("Node click - data:", data);
     *           console.log("Node click - this:", this);
     *         }
     *     );
     *
     * If used as APEX plugin you can also create an APEX dynamic action on the component event “Node Click [D3 - Force Layout]” on your graph region. If you do so, you can access the event and data by executing JavaScript code in this way:
     *
     *     console.log("Node click - event:", this.browserEvent);
     *     console.log("Node click - data:", this.data);
     *
     * Please refer also to the APEX dynamic action documentation and keep in mind, that the data is the same in both ways but the event differs, because APEX provide a jQuery event and the Plugin the D3 original event.
     * @param {Object} [eventFunction] - The new function.
     * @returns {Object} The current function if no parameter is given or the graph object for method chaining.
     */
    graph.onNodeClickFunction = function(value) {
        if (!arguments.length) {
            return v.conf.onNodeClickFunction;
        }
        v.conf.onNodeClickFunction = value;
        return graph;
    };

    /**
     * Gets or sets the function for the node dblclick event.
     *
     * In the first two parameters you get the event and the d3 node data, inside your function you have access to the DOM node with the this keyword:
     *
     *     example.onNodeDblclickFunction(
     *         function(event, data){
     *           console.log("Node double click - event:", event);
     *           console.log("Node double click - data:", data);
     *           console.log("Node double click - this:", this);
     *         }
     *     );
     *
     * If used as APEX plugin you can also create an APEX dynamic action on the component event “Node Double Click [D3 - Force Layout]” on your graph region. If you do so, you can access the event and data by executing JavaScript code in this way:
     *
     *     console.log("Node double click - event:", this.browserEvent);
     *     console.log("Node double click - data:", this.data);
     *
     * Please refer also to the APEX dynamic action documentation and keep in mind, that the data is the same in both ways but the event differs, because APEX provide a jQuery event and the Plugin the D3 original event.
     * @param {Object} [eventFunction] - The new function.
     * @returns {Object} The current function if no parameter is given or the graph object for method chaining.
     */
    graph.onNodeDblclickFunction = function(value) {
        if (!arguments.length) {
            return v.conf.onNodeDblclickFunction;
        }
        v.conf.onNodeDblclickFunction = value;
        return graph;
    };

    /**
     * Gets or sets the function for the node contextmenu event.
     *
     * In the first two parameters you get the event and the d3 node data, inside your function you have access to the DOM node with the this keyword:
     *
     *     example.onNodeContextmenuFunction(
     *         function(event, data){
     *           console.log("Node contextmenu - event:", event);
     *           console.log("Node contextmenu - data:", data);
     *           console.log("Node contextmenu - this:", this);
     *         }
     *     );
     *
     * If used as APEX plugin you can also create an APEX dynamic action on the component event “Node Contextmenu [D3 - Force Layout]” on your graph region. If you do so, you can access the event and data by executing JavaScript code in this way:
     *
     *     console.log("Node contextmenu - event:", this.browserEvent);
     *     console.log("Node contextmenu - data:", this.data);
     *
     * Please refer also to the APEX dynamic action documentation and keep in mind, that the data is the same in both ways but the event differs, because APEX provide a jQuery event and the Plugin the D3 original event.
     * @param {Object} [eventFunction] - The new function.
     * @returns {Object} The current function if no parameter is given or the graph object for method chaining.
     */
    graph.onNodeContextmenuFunction = function(value) {
        if (!arguments.length) {
            return v.conf.onNodeContextmenuFunction;
        }
        v.conf.onNodeContextmenuFunction = value;
        return graph;
    };

    /**
     * Gets or sets the function for the lassostart event.
     *
     * In the first two parameters you get the event and the d3 lasso data, inside your function you have access to the DOM node with the this keyword. In case of the lasso this is refering the svg container element, because the lasso itself is not interesting:
     *
     *     example.onLassoStartFunction(
     *         function(event, data){
     *           console.log("Lasso start - event:", event);
     *           console.log("Lasso start - data:", data);
     *           console.log("Lasso start - this:", this);
     *         }
     *     );
     *
     * If used as APEX plugin you can also create an APEX dynamic action on the component event “Lasso Start [D3 - Force Layout]” on your graph region. If you do so, you can access the event and data by executing JavaScript code in this way:
     *
     *     console.log("Lasso start - event:", this.browserEvent);
     *     console.log("Lasso start - data:", this.data);
     *
     * Please refer also to the APEX dynamic action documentation and keep in mind, that the data is the same in both ways but the event differs, because APEX provide a jQuery event and the Plugin the D3 original event.
     * @param {Object} [eventFunction] - The new function.
     * @returns {Object} The current function if no parameter is given or the graph object for method chaining.
     */
    graph.onLassoStartFunction = function(value) {
        if (!arguments.length) {
            return v.conf.onLassoStartFunction;
        }
        v.conf.onLassoStartFunction = value;
        return graph;
    };

    /**
     * Gets or sets the function for the lassoend event.
     *
     * In the first two parameters you get the event and the d3 lasso data, inside your function you have access to the DOM node with the this keyword. In case of the lasso this is refering the svg container element, because the lasso itself is not interesting:
     *
     *     example.onLassoEndFunction(
     *         function(event, data){
     *           console.log("Lasso end - event:", event);
     *           console.log("Lasso end - data:", data);
     *           console.log("Lasso end - this:", this);
     *         }
     *     );
     *
     * If used as APEX plugin you can also create an APEX dynamic action on the component event “Lasso End [D3 - Force Layout]” on your graph region. If you do so, you can access the event and data by executing JavaScript code in this way:
     *
     *     console.log("Lasso end - event:", this.browserEvent);
     *     console.log("Lasso end - data:", this.data);
     *
     * Please refer also to the APEX dynamic action documentation and keep in mind, that the data is the same in both ways but the event differs, because APEX provide a jQuery event and the Plugin the D3 original event.
     * @param {Object} [eventFunction] - The new function.
     * @returns {Object} The current function if no parameter is given or the graph object for method chaining.
     */
    graph.onLassoEndFunction = function(value) {
        if (!arguments.length) {
            return v.conf.onLassoEndFunction;
        }
        v.conf.onLassoEndFunction = value;
        return graph;
    };

    /**
     * Gets or sets the sample data. This makes only sense before the first start, because only on the first start without data available the sample data is used. After the first start you can provide new data with the start method. Example:
     *
     *     //first start
     *     example.sampleData('<node>...').start();
     *
     *     //later
     *     example.start('<node>...');
     * @see {@link module:API.start}
     * @param {(string|Object)} [data] - The new sample data as XML string, JSON string or JSON object.
     * @returns {Object} The current sample data in JSON format if no parameter is given or the graph object for method chaining.
     */
    graph.sampleData = function(data) {
        if (!arguments.length) {
            return v.data.sampleData;
        }
        v.data.sampleData = data;
        return graph;
    };


    /**
     * Returns the current graph data as JSON object. This method expects no parameter and terminates the method chain. Example:
     *
     *     //JSON object
     *     example.data();
     *
     *     //stringified JSON object
     *     JSON.stringify(example.data());
     * @see {@link module:API.nodeDataById}
     * @see {@link module:API.start}
     * @returns {Object} The current graph data.
     */
    graph.data = function() {
        return v.data.dataConverted;
    };

    /**
     * Returns the data from a specific node as JSON object. This method expects a node ID as parameter and terminates the method chain. Example:
     *
     *     //get the data from the node with the ID 8888
     *     example.nodeDataById('8888');
     *
     *     //get the data from the node with the ID 'myAlphanumericID'
     *     example.nodeDataById('myAlphanumericID');
     * @see {@link module:API.data}
     * @param {string} id - The node id.
     * @returns {Object} The node data.
     */
    graph.nodeDataById = function(id) {
        return v.data.idLookup[id];
    };

    /**
     * Get or set the whole configuration with one call. Ouput includes all options, which are accessible via the API methods including the registered event functions:
     *
     *     //get the current configuration
     *     example.options();
     *     //set the new configuration
     *     example.options( { pinMode: true, ... } );
     * @see {@link module:API.optionsCustomizationWizard}
     * @param {Object} [options] - Your new options.
     * @returns {Object} Your current options or the graph object for method chaining.
     */
    graph.options = function(options) {
        var key;
        if (!arguments.length) {
            var conf = {};
            for (key in v.conf) {
                if (v.conf.hasOwnProperty(key)) {
                    if (v.confDefaults.hasOwnProperty(key)) {
                        if ((v.confDefaults[key].type === "bool" ||
                                v.confDefaults[key].type === "number" ||
                                v.confDefaults[key].type === "text") &&
                            v.confDefaults[key].val !== v.conf[key]) {
                            conf[key] = v.conf[key];
                        } else if (v.confDefaults[key].type === "object" &&
                            JSON.stringify(v.confDefaults[key].val) !== JSON.stringify(v.conf[key])) {
                            conf[key] = v.conf[key];
                        }
                    } else if (!v.confDefaults.hasOwnProperty(key) &&
                        v.conf[key] !== undefined &&
                        v.conf[key] !== null) {
                        conf[key] = v.conf[key];
                    }
                }
            }
            return conf;
        } else {
            v.tools.applyConfigurationObject(options);
            return graph;
        }
    };

    /**
     * Get or set the whole configuration with one call. Output includes only the options, which are accessible via the customization wizard:
     *
     *     //get the current configuration
     *     example.optionsCustomizationWizard();
     *     //set the new configuration
     *     example.optionsCustomizationWizard( { pinMode: true, ... } );
     * @see {@link module:API.options}
     * @param {Object} [options] - Your new options.
     * @returns {Object} Your current options or the graph object for method chaining.
     */
    graph.optionsCustomizationWizard = function(options) {
        var key;
        if (!arguments.length) {
            var conf = {};
            for (key in v.confDefaults) {
                if (v.confDefaults.hasOwnProperty(key)) {
                    if ((v.confDefaults[key].type === "bool" ||
                            v.confDefaults[key].type === "number" ||
                            v.confDefaults[key].type === "text") &&
                        v.confDefaults[key].val !== v.conf[key]) {
                        conf[key] = v.conf[key];
                    } else if (v.confDefaults[key].type === "object" &&
                        JSON.stringify(v.confDefaults[key].val) !== JSON.stringify(v.conf[key])) {
                        conf[key] = v.conf[key];
                    }
                }
            }
            return conf;
        } else {
            v.tools.applyConfigurationObject(options);
            return graph;
        }
    };

    /**
     * Gets or sets the customize mode. If true, the customizing wizard is opened, otherwise closed.
     *
     *     example.customize(true);
     * @see {@link module:API.debug}
     * @param {boolean} [value] - The new mode.
     * @returns {(boolean|Object)} The current mode if no parameter is given or the graph object for method chaining.
     */
    graph.customize = function(value) {
        if (!arguments.length) {
            return v.status.customize;
        }
        v.status.customize = value;
        if (v.status.graphStarted) {
            if (v.status.customize) {
                v.tools.createCustomizeWizard();
                v.tools.removeCustomizeLink();
            } else {
                v.tools.removeCustomizeWizard();
                if (v.conf.debug) {
                    v.tools.createCustomizeLink();
                }
            }
        }
        return graph;
    };

    /**
     * Gets or sets the debug mode. When debug is enabled, there is a link rendered in the SVG to start the customize wizard and debug messages are written to the console.
     *
     *     example.debug(true);
     * @see {@link module:API.customize}
     * @param {boolean} [value] - The new mode.
     * @returns {(boolean|Object)} The current mode if no parameter is given or the graph object for method chaining.
     */
    graph.debug = function(value) {
        if (!arguments.length) {
            return v.conf.debug;
        }
        v.conf.debug = value;
        if (v.status.graphStarted) {
            if (v.conf.debug) {
                v.tools.createCustomizeLink();
            } else {
                v.tools.removeCustomizeLink();
            }
        }
        return graph;
    };

    /**
     * Returns the detected user agent. Expects no parameter and terminates the method chain:
     *
     *     example.userAgent();
     * @see {@link module:API.inspect}
     * @returns {string} The detected user agent.
     */
    graph.userAgent = function() {
        return v.status.userAgent;
    };

    /**
     * Shows the current closure object, which holds all functions and data. This method expects no parameter and terminates the method chain:
     *
     *     example.inspect();
     * @see {@link module:API.userAgent}
     * @returns {Object} The graph's internal object with all functions and data.
     */
    graph.inspect = function() {
        return v;
    };

    /**
     * Shows the current plugin version. This method expects no parameter and terminates the method chain:
     *
     *     example.version();
     * @see {@link module:API.userAgent}
     * @returns {string} The plugin version.
     */
    graph.version = function() {
        return v.version;
    };

    /*******************************************************************************************************************
     * Startup code - runs one time after the initialization of a new chart - example:
     * var myChart = net_gobrechts_d3_force( domContainerId, pConf, apexPluginId ).start();
     */

    if (v.status.apexPluginId) {
        // bind to the apexrefresh event, so that this region can be refreshed by a dynamic action
        apex.jQuery("#" + v.dom.containerId).bind("apexrefresh", function() {
            graph.start();
        });
        //rerender on window resize
        apex.jQuery(window).on("apexwindowresized", function() {
            graph.render();
        });
        apex.jQuery("#t_Button_navControl").click(function() {
            setTimeout(function() {
                graph.render();
            }, 500);
        });

    }


    // final return
    return graph;

}
