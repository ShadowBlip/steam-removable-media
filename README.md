# steam-removable-media
Automounts and imports removable media as a Steam library

# Installing

## From the AUR
- Run ```pikaur -S steam-removable-media-git``` as root.

## From source
- Install parted
- Run ```./install.sh``` as root.


# Removing

## From the AUR
- Run ```pikaur -R steam-removable-media-git``` as root.

## From source
- Run ```./remove.sh``` as root.

# Configuring
To support the 'Format SD Card' button in Steam GamepadUI you will need to
ensure your user has NOPASSWD access to the scripts.

`touch /etc/suoders.d/media-support`
use your preffered text editor to add the following.
```
gamer ALL=(ALL) NOPASSWD: /usr/lib/hwsupport/format-sdcard.sh*
gamer ALL=(ALL) NOPASSWD: /usr/lib/media-support/format-media.sh*
```


