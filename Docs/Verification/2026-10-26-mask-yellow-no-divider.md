# Active mask highlight and bottom divider

Removed the bottom photo toolbar's Divider overlay, which inherited the enclosing
horizontal layout and appeared vertically through the rating stars. The intended
view/sort separator remains.

The active mask's name/icon use the preset accent yellow, with a subtle yellow
row background and selected accessibility trait. Other masks remain neutral;
switching rows moves the highlight to the current selection.

No simulator or automated tests run. Device build/sign/install evidence is under
LocalVerification/mask-yellow-no-divider-*; hands-on acceptance is with the user.

Delivery: device build and strict signature verification passed. Installation on
the iPad succeeded, sequence 2724. The app was not launched.
