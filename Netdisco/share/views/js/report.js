  // used by the tabbing interface to make sure the correct
  // ajax content is loaded
  var path = 'report';

  // this is called by do_search to support local code
  // here, when tab changes need to strike/unstrike the navbar search
  function inner_view_processing(tab) { }

  // on load, check initial Device Search Options form state,
  // and on each change to the form fields
  $(document).ready(function() {
    var tab = '[% report.tag %]'
    var target = '#' + tab + '_pane';
  });

