/**
 * The following plug-in uses a modified version of the [naturalSort() function by Jim
 * Palmer](http://www.overset.com/2008/09/01/javascript-natural-sort-algorithm-with-unicode-support) to provide natural sorting in DataTables.
 *
 *  @name portsort.js
 *  @summary Sort network device port names with a mix of numbers and letters with modified natural sort.
 *  @author [Jim Palmer](http://www.overset.com/2008/09/01/javascript-natural-sort-algorithm-with-unicode-support)
 *
 *  @example
 *    new DataTable('#example', {
 *       columnDefs: [
 *         { type: 'portsort', targets: 0 }
 *       ]
 *    } );
 */

(function() {

/*
 * Based upon the Natural Sort algorithm for Javascript
 * Version 0.7 - Released under MIT license
 * Author: Jim Palmer (based on chunking idea from Dave Koelle)
 * Contributors: Mike Grier (mgrier.com), Clint Priest, Kyle Adams, guillermo
 * See: http://js-naturalsort.googlecode.com/svn/trunk/naturalSort.js
 */
function portSort (a, b) {
    var re = /(^0x[0-9a-f]+$|[0-9]+)/gi,
        // string regex
        sre = /(^[ ]*|[ ]*$)/g,
        // octal regex
        ore = /^0/,
        // convert all to strings and trim()
        x = a.toString().replace(sre, '') || '',
        y = b.toString().replace(sre, '') || '';

    // hack for foundry "10GigabitEthernet" -> cisco-like "TenGigabitEthernet"
    x = x.replace(/^10GigabitEthernet/, 'GigabitEthernet');
    y = y.replace(/^10GigabitEthernet/, 'GigabitEthernet');

    // chunk/tokenize
    var xN = x.replace(re, '\0$1\0').replace(/\0$/,'').replace(/^\0/,'').split('\0'),
        yN = y.replace(re, '\0$1\0').replace(/\0$/,'').replace(/^\0/,'').split('\0');

    for (var cLoc=0, numS=Math.max(xN.length, yN.length); cLoc < numS; cLoc++) {
        // find floats not starting with '0', string or 0 if not defined (Clint Priest)
        var oFxNcL = !(xN[cLoc] || '').match(ore) && parseFloat(xN[cLoc]) || xN[cLoc] || 0;
        var oFyNcL = !(yN[cLoc] || '').match(ore) && parseFloat(yN[cLoc]) || yN[cLoc] || 0;

        // handle numeric vs string comparison - number < string - (Kyle Adams)
        if (isNaN(oFxNcL) !== isNaN(oFyNcL)) {
            return (isNaN(oFxNcL)) ? 1 : -1;
        }
        // rely on string comparison if different types - i.e. '02' < 2 != '02' < '2'
        else if (typeof oFxNcL !== typeof oFyNcL) {
            oFxNcL += '';
            oFyNcL += '';
        }

        if (oFxNcL < oFyNcL) { return -1; }
        if (oFxNcL > oFyNcL) { return 1;  }
    }

    return 0;
}

// A pairwise comparator and deliberately not a pre-formatter: each chunk is
// coerced to a number or to a string depending on what the other value's chunk
// turned out to be, so no key computed from one value on its own reproduces the
// order.
DataTable.type('portsort', {
    order: {
        asc: function ( a, b ) {
            return portSort(a,b);
        },

        desc: function ( a, b ) {
            return portSort(a,b) * -1;
        }
    }
});

}());
