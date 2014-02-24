

$(function() {
  var storyButtons = $(".nextstate input[type=submit]");
  storyButtons.click(function(e) {
    e.preventDefault();
    var form = $(e.target).closest("form");
    updateStory(form);
  });
});

function updateStory(form) {
  $("#swimlanes").addClass("loading");
  $.ajax({
    type: "POST",
    url: form.attr("action"),
    data: form.serialize(),
    success: updatePage,
    dataType: "html" 
  });
}

function updatePage(e) {
  $("body").html($(e));
  $('html, body').animate({
    scrollTop: $("#" + window.location.hash.substring(1)).offset().top
  }, 0);
}
