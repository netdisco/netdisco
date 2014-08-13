/**
 * Netdisco utility functions
 * @version 0.0.1
 * @license bsd
 * @copyright 2014 Netdisco developers
 */

/** Capitalize first letter of a string. */

function capitalizeFirstLetter(string) {
  return string.charAt(0).toUpperCase() + string.slice(1);
}

/**
 * Formats a MAC address string.
 * @function
 * @param {string} macaddr - MAC address provided in IEEE, Microsoft, or Sun format.
 * @param {string} format - Format to return must be either 'IEEE', 'Cisco', 'Microsoft', or 'Sun'.
 */

function formatMacAddress(macaddr, format) {
  var mac = /^([0-9A-F]{2}[:-]){5}([0-9A-F]{2})$/i;
  var fmt = /^(IEEE|Cisco|Microsoft|Sun)$/i;
  var fmac = '';

  if (!mac.test(macaddr) || !fmt.test(format)) {
    return macaddr;
  } else {
    macaddr = macaddr.replace(/[:-]/g, "").toLowerCase();
    format = format.toLowerCase();
    switch (format) {
      case 'ieee':
        fmac = convertMacAddress(macaddr, ":", 2).toUpperCase();
        break;

      case 'cisco':
        fmac = convertMacAddress(macaddr, ".", 4);
        break;

      case 'microsoft':
        fmac = convertMacAddress(macaddr, "-", 2).toUpperCase();
        break;

      case 'sun':
        fmac = convertMacAddress(macaddr, ":", 2);
        fmac = fmac.replace(/0([0-9A-F])/gi, '$1');
        break;

      default:
        fmac = macaddr;
        break;
    }
  }

  function convertMacAddress(string, chr, nth) {
    var retval = '';
    for (var i = 0; i < string.length; i++) {
      if (i > 0 && i % nth == 0)
        retval += chr;
      retval += string.charAt(i);
    }

    return retval;
  }

  return fmac;
}