# steam-removable-media
Automounts and imports removable media as a Steam library.
Devices must be formated as ext4 or they will not work.
Supported device types:
```
mmcblkX
nvmeX
sdX
```

# Usage
See the [wiki](https://github.com/ShadowBlip/steam-removable-media/wiki) for detailed usage instructions.

# Installing

## From the AUR
`yay -Sy steam-removable-media-git`

## From source
```
yay -Sy --needed parted
git clone https://github.com/ShadowBlip/steam-removable-media.git && cd steam-removable-media
sudo ./install.sh.
```

# Removing

## From the AUR
'yay -R steam-removable-media-git`

## From source
```
cd steam-removable-media
sudo ./remove.sh
```
