/**
 * The following plug-in uses a modified version of the [naturalSort() function by Jim
 * Palmer](http://www.overset.com/2008/09/01/javascript-natural-sort-algorithm-with-unicode-support) to provide natural sorting in DataTables.
 *
 *  @name naturalsort.js
 *  @summary Sort software version number with a mix of numbers and letters with natural sort.
 *  @author [Jim Palmer](http://www.overset.com/2008/09/01/javascript-natural-sort-algorithm-with-unicode-support)
 *
 *  @example
 *    $('#example').dataTable( {
 *       columnDefs: [
 *         { type: 'versionsort', targets: 0 }
 *       ]
 *    } );
 */

function pad(datum, size) {
    var s = "000000000" + datum;
    return s.substr(s.length-size);
}

(function() {

/*
 * Natural Sort algorithm for Javascript - Version 0.7 - Released under MIT license
 * Author: Jim Palmer (based on chunking idea from Dave Koelle)
 */
/*jshint unused:false */
function versionSort (a, b) {
    "use strict";
    var pada = a.split(/(\D)/).map(x => pad(x, 5)).join('');
    var padb = b.split(/(\D)/).map(x => pad(x, 5)).join('');
    if ( pada < padb ) { return -1; }
    else if ( pada > padb ) { return 1; }
    return 0;
};

jQuery.extend( jQuery.fn.dataTableExt.oSort, {
    "versionsort-asc": function ( a, b ) {
        return versionSort(a,b);
    },

    "versionsort-desc": function ( a, b ) {
        return versionSort(a,b) * -1;
    }
} );

}());
