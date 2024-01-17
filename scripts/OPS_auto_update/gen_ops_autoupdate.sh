#!/usr/bin/env bash

export DISPLAY=:0

########## Function to send the logs to swupdate.log ####################
log_gen() {
  echo "$(date "+%F %T"): "$1"" >> /media/persistent/fcc/swupdate.log;
}
CURRENT_VERSION=`cat /etc/package_num`
regex="^([0-9]+)\.([0-9]+)(\.([0-9]+))?$"
if [[ $CURRENT_VERSION =~ $regex ]]
then
    CURR_XX=${BASH_REMATCH[1]};
    CURR_YY=${BASH_REMATCH[2]};
    CURR_ZZ=${BASH_REMATCH[4]};
fi
PACKAGE_FILEPATH=$(find /media/sda1/ -type f -name "*Package_[0-9.]*.swu")
regex=".*SC4500_Update_[0-9_]+Package_([0-9]+)\.([0-9]+)(\.([0-9]+))?\.swu$"
if [[ "$PACKAGE_FILEPATH" =~ $regex ]];
then
  NEW_XX=${BASH_REMATCH[1]};
  NEW_YY=${BASH_REMATCH[2]};
  NEW_ZZ=${BASH_REMATCH[4]};
  # Condition check. First check with XX numbers. 
  # If they are equal, the comparison goes to YY. 
  # If they are equal too, last comparison is about ZZ numbers.
  if [[ $NEW_XX > $CURR_XX ]] ||
    ([[ $NEW_XX == $CURR_XX ]] && [[ $NEW_YY > $CURR_YY ]]) ||
    ([[ $NEW_XX == $CURR_XX ]] && [[ $NEW_YY == $CURR_YY ]] && [[ $NEW_ZZ > $CURR_ZZ ]]);
  then
    log_gen "New update is available"
    if [ -d /tmp/swupdate_file/ ];
    then
      log_gen "swupdate_file directory already exists. Removing..."
      rm -r /tmp/swupdate_file
    fi
    mkdir /tmp/swupdate_file
    display -size 320x240 -backdrop /tmp/HACH_UPDATE_FILE_COPYING_320x240.bmp &
    cp "$PACKAGE_FILEPATH" /tmp/swupdate_file/ # Copying the file into temporary folder of the controller
    log_gen "Update version file copied to /tmp/swupdate_file/ temporary directory"
    TEMP_PACKAGE_FILEPATH="$(find /tmp/swupdate_file/ -name "*.swu")" # Temporary file path in the controller
    # Starting background task to launch the system update.This is needed because it´s
    # not possible to launch two nested swupdate commands.The one second wait is set to
    { 
      # Wait 1 second to let the system show the green lock already defined in swupdate_unlock.sh
      # and then overwrite it with the new screen
      sleep 1;
      display -size 320x240 -backdrop /tmp/HACH_USB_UPDATE_320x240.bmp &
      log_gen "Updating system...";
      while true
      do
        swupdate-client -v "$TEMP_PACKAGE_FILEPATH";
        result="$?";
        [[ !("$result") ]] && break;
        # 0.5 seconds delay in order to avoid calling
        # swupdate-client in a very fast loop
        sleep 0.5;
      done; 
    } &
  else
    log_gen "Already at latest version"
    {
      # Wait 1 second to let the system show the green lock already defined in swupdate_unlock.sh
      # and then overwrite it with the new screen
      sleep 1;
      timeout -t 30 display -size 320x240 -backdrop /tmp/HACH_UP_TO_DATE_320x240.bmp &
    } &
  fi
else
 log_gen "No proper update file found"
fi


