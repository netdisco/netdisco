/**
 * Sorts a column containing IP addresses in typical dot notation. This can 
 * be most useful when using DataTables for a networking application, and 
 * reporting information containing IP address. Also has a matching type 
 * detection plug-in for automatic type detection.
 *
 *  @name IP addresses 
 *  @summary Sort IP addresses numerically
 *  @author Brad Wasson
 *
 *  @example
 *    new DataTable('#example', {
 *       columnDefs: [
 *         { type: 'ip-address', targets: 0 }
 *       ]
 *    } );
 */

// A pre-formatter: left padding every octet to three digits makes one key per
// value that orders as text, so no pairwise comparison of the octets is needed.
DataTable.type('ip-address', {
	order: {
		pre: function ( a ) {
			// Same reason as the detector strips markup: an anchor's href holds
			// dots of its own, so splitting the raw cell keys on the URL rather
			// than on the address.
			var text = String(a == null ? '' : a).replace(/<[^>]*>/g, '').trim();
			var m = text.split("."), x = "";

			for(var i = 0; i < m.length; i++) {
				var item = m[i];
				if(item.length == 1) {
					x += "00" + item;
				} else if(item.length == 2) {
					x += "0" + item;
				} else {
					x += item;
				}
			}

			return x;
		},

		asc: function ( a, b ) {
			return ((a < b) ? -1 : ((a > b) ? 1 : 0));
		},

		desc: function ( a, b ) {
			return ((a < b) ? 1 : ((a > b) ? -1 : 0));
		}
	}
});
