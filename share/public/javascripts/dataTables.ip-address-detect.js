/**
 * Automatically detect IP addresses in dot notation. Goes perfectly with the
 * IP address sorting function.
 *
 *  @name IP address detection
 *  @summary Detect data which is in IP address notation
 *  @author Brad Wasson
 */

(function() {

// Named once and returned by the detector, because the name registered here and
// the name the detector answers with have to be the same string as the one
// dataTables.ip-address-sort.js registers its order under. Disagree, and every
// dotted quad in the product falls back to text order with nothing failing.
var TYPE = 'ip-address';

DataTable.type(TYPE, {
	detect: function ( data )
	{
		// netdisco links most of the addresses it prints, so the cell reaching
		// here is markup and the plain pattern never matched: every linked
		// address in the product fell back to text order, putting .70 above .4.
		var text = DataTable.util.stripHtml(String(data == null ? '' : data)).trim();
		if (/^\d{1,3}[\.]\d{1,3}[\.]\d{1,3}[\.]\d{1,3}$/.test(text)) {
			return TYPE;
		}
		return false;
	}
});

}());
