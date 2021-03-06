# Backup System
Backup System is a live Linux to automatically create incremental backups.

After booting the backup system you are asked whether you want to create a
backup. If you confirm this, you are prompted for the passwords of all LUKS
encrypted partitions involved in the backup process. Then the backup is
created and the computer shuts down when it completed the backup process. All
backup options are configured using a configuration file. See the
Configuration section for details.

## Idea
Locally installed backup solutions have the downside that your choice of
operating system partially determines your choice of backup program. Thus, if
you use multiple operating systems, you will have to use many different
programs to create backups. The idea of this backup system is to create an
operating system and system state independent backup solution. This is
achieved by using a live Linux which creates the backup.

Apart from booting the backup system the backup process is completely
automated. This means you only have to confirm that you want to create a
backup and enter the passwords for LUKS encrypted devices. All other aspects
of the backup process are controlled by a configuration file.

## Building Instructions
For building the backup live linux, the debian package linux-live is used. For
documentation see their web site. You probably will have to search for
it. The last time I looked it was located at

https://live-team.pages.debian.net/live-manual/

This building instruction was tested on a Debian Buster machine.

### Prerequisites
You need the following software for installation:
  * live-build
  * make

Alternatively, you can use a docker image to build Backup System. In that
case, you will need
  * docker
  * make

### Building an ISO image
Make sure to setup the configuration correctly. See the Configuration section
for details. Then you can build the image by running the following command

```Shell
make iso
```

Between subsequent builds, the command `make clean` should be ran to clean up the
previous build. If you want to clean all automatically generated files, run
`make clean-all`.

### Building using Docker
To build Backup System using Docker, you can prefix the make targets from
above with the prefix `builder-`. For example, if you want to create the ISO
image version you can run `make builder-iso`.

To build the docker image which is used for building Backup System you can run
`make builder`. If the docker image is non existent when running any of the
build commands using docker, the image is automatically created. To keep track
on the build status of the docker image, the (empty) state file `builder` is
created. Its presence indicates that the docker image has been built. Thus, if
you need to rebuild the docker image, delete the file `builder` in the project
root folder.

You can run the docker image interactively by running `make run`.

Note: Sometimes the build using docker fails. It can help to just try again
without changing anything.

### Creating a bootable USB drive
If you have trouble creating the bootable USB-drive, take a look at [Will
Haley's Debian live Linux building
instructions](https://willhaley.com/blog/custom-debian-live-environment/). These
instructions are build on his blog entry.

## Configuration
### Backup Configuration
The backup configuration is stored in the XML-file `backup.xml` located in the
root directory of the live medium. If you are using the ISO export, you should
copy the `backup.xml` file to the folder `config/includes.binary` prior to a
build. This deploys the file into the root directory of the generated ISO
image.

### Keyboard Configuration
The keyboard configuration can be altered in two different ways. If the backup
system is a bootable USB drive, you can edit the boot prompt inside the
Syslinux boot files. If you use a burned version of the generated ISO image,
you have to edit the boot prompt using the file `auto/config`. In there edit
the keyboard options `--boot-append-live`. See [The Debian Live
Manual](https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-run-time-behaviours.en.html#532)
for details on how to specify your desired keyboard layout.

The default keyboard configuration is a German keyboard layout.
