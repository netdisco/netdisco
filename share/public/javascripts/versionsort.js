/**
 * The following plug-in uses a modified version of the [naturalSort() function by Jim
 * Palmer](http://www.overset.com/2008/09/01/javascript-natural-sort-algorithm-with-unicode-support) to provide natural sorting in DataTables.
 *
 *  @name naturalsort.js
 *  @summary Sort software version number with a mix of numbers and letters with natural sort.
 *  @author [Jim Palmer](http://www.overset.com/2008/09/01/javascript-natural-sort-algorithm-with-unicode-support)
 *
 *  @example
 *    new DataTable('#example', {
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
function versionKey (datum) {
    "use strict";
    return datum.split(/(\D)/).map(x => pad(x, 5)).join('');
}

// A pre-formatter and not a pairwise comparator: the comparison is a plain
// relational test between two keys each built from one value alone, so the key
// is built once per value rather than once per comparison. The two comparators
// spell that relational test out rather than leaving it to whatever the library
// does for a type registering none, so an upgrade cannot move the order.
DataTable.type('versionsort', {
    order: {
        pre: versionKey,

        asc: function ( a, b ) {
            if ( a < b ) { return -1; }
            else if ( a > b ) { return 1; }
            return 0;
        },

        desc: function ( a, b ) {
            if ( a < b ) { return 1; }
            else if ( a > b ) { return -1; }
            return 0;
        }
    }
});

}());
