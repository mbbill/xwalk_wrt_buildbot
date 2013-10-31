#!/bin/bash
#<bai.ming@intel.com>

if [[ $UID == 0 ]]; then
	echo "Running this under root is bad.."
	exit
fi

XWALK_LINUX="/ssd/xwalk_linux/src/xwalk"
XWALK_ANDROID="/ssd/xwalk_android/src/xwalk"
XWALK_WIN="/host_share/src/xwalk"

BUILDBOT_ROOT="/var/www/buildbot"
UPLOAD="${BUILDBOT_ROOT}/upload"
OUTPUT="${BUILDBOT_ROOT}/output"
LOG="${BUILDBOT_ROOT}/log"
STATUS="${BUILDBOT_ROOT}/status"
TMPDIR="${BUILDBOT_ROOT}/tmp"

export PATH=/usr/lib/ccache:/ssd/depot_tools:/ssd/jdk1.7.0_40/bin:$PATH

while true; do
	#Do some necessary check.
	if  ! [[ -d $UPLOAD ]]; then
		echo "Error reading upload directory: $UPLOAD"
		break;
	fi
	if  ! [[ -d $OUTPUT ]]; then
		echo "Error reading output directory: $OUTPUT"
		break;
	fi

	cd $BUILDBOT_ROOT

	#Check uploaded files.
	TARBALL=$(find ${UPLOAD} -name '*.tar.gz')
	if [[ $TARBALL == "" ]]; then
		echo "Waiting for upload..."
		echo "Idle" > $STATUS
		inotifywait $UPLOAD -e CLOSE_WRITE
		continue
	fi

	#There are something...
	echo "Building." > $STATUS
	if [[ $(echo $TARBALL | wc -l) != 1 ]]; then
		echo "More than 1 tarball found, process one by one"
	fi
	TARBALL=$(echo $TARBALL | head -n1)
	echo "$(date +%D_%T) $(basename $TARBALL) uploaded" >>$LOG
	
	#Brief check if it's a gzip package
	if [[ $(file $TARBALL | grep gzip) == "" ]]; then
		echo "$TARBALL is not a gzip package, put to tmp"
			mv $TARBALL $TMPDIR
		continue
	fi

	#Okay, now we're just about ready to start
	#Prepare the output directory
	DIR_TODAY=${OUTPUT}/$(date +%F)
	if ! [[ -d $DIR_TODAY ]]; then
		mkdir $DIR_TODAY
	fi

	#Let's begin
	echo "$(date +%D_%T) $(basename $TARBALL) start build..." >>$LOG
	CURRENT_DIR=${DIR_TODAY}/$(date +%s)_$(basename ${TARBALL%.tar.gz})
	mkdir $CURRENT_DIR
	mv $TARBALL $CURRENT_DIR
	TARBALL=${CURRENT_DIR}/$(basename $TARBALL)
	CLOG=${CURRENT_DIR}/log

	#Build Linux version first.
	if  ! [[ -d $XWALK_LINUX ]]; then
		echo "Error reading xwalk directory: $XWALK_LINUX" >> $LOG
		break;
	fi
	#Clean up the previous source
	rm -rf $XWALK_LINUX/*
	#extract new code
	tar xvf $TARBALL -C $XWALK_LINUX > /dev/null
	#touch every file to eliminate modify time mismatch
	find $XWALK_LINUX -exec touch {} \;
	#Start
	cd $XWALK_LINUX
	cd ..
	#lint
	echo "lint.py --repo=xwalk >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" >> $CLOG
	python xwalk/tools/lint.py --repo=xwalk >>$CLOG 2>&1
	#Do these tasks in a subshell
	echo "Building Linux >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" >> $CLOG
	(
	#Clean up the previous .ninja files.
	find out -name '*.ninja' -exec rm {} \;
	export GYP_GENERATORS='ninja'
	python xwalk/gyp_xwalk >>$CLOG 2>&1
	if [[ $? != 0 ]]; then
		exit 1
	fi
	ninja -C out/Release xwalk xwalk_browsertest xwalk_unittest >>$CLOG 2>&1
	if [[ $? != 0 ]]; then
		exit 1
	fi
	echo "Running unittest >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" >> $CLOG
	./out/Release/xwalk_unittest >>$CLOG 2>&1
	if [[ $? != 0 ]]; then
		exit 1
	fi
	echo "Running browsertest >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" >> $CLOG
	./out/Release/xwalk_browsertest >>$CLOG 2>&1
	if [[ $? != 0 ]]; then
		exit 1
	fi
	)
	#if [[ $? == 1 ]]; then
	#	echo "Build failed." >> $CLOG
	#	continue
	#fi

	#Build android.
	echo "Building Android >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" >> $CLOG
	if  ! [[ -d $XWALK_ANDROID ]]; then
		echo "Error reading xwalk directory: $XWALK_ANDROID" >> $LOG
		break;
	fi
	#Clean up the previous source
	rm -rf $XWALK_ANDROID/*
	#extract new code
	tar xvf $TARBALL -C $XWALK_ANDROID > /dev/null
	find $XWALK_ANDROID -exec touch {} \;
	#Build
	cd $XWALK_ANDROID
	cd ..
	#subshell
	(
	#Clean up the previous .ninja files.
	find out -name '*.ninja' -exec rm {} \;
	. xwalk/build/android/envsetup.sh --target-arch=x86
	export GYP_GENERATORS='ninja'
	xwalk_android_gyp >>$CLOG 2>&1
	if [[ $? != 0 ]]; then
		exit 1
	fi
	ninja -C out/Release xwalk_core_shell_apk xwalk_runtime_shell_apk >>$CLOG 2>&1
	if [[ $? != 0 ]]; then
		exit 1
	fi
	)
	#if [[ $? == 1 ]]; then
	#	echo "Build failed." >> $CLOG
	#	continue
	#fi

	#Build windows
	echo "Building Windows >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" >> $CLOG
	if  ! [[ -d $XWALK_WIN ]]; then
		echo "Error reading xwalk directory: $XWALK_ANDROID" >> $LOG
		break;
	fi
	#Clean up the previous source
	rm -rf $XWALK_WIN/*
	tar xvf $TARBALL -C $XWALK_WIN > /dev/null
	find $XWALK_WIN -exec touch {} \;
	#Build, we ssh into the host machine and issue the build command
	ssh -p22322 build@bming-desk1.ccr.corp.intel.com 'cd /cygdrive/c/Users/build/xwalk && cmd /c build_ninja.bat' >> $CLOG 2>&1

	#done
	echo "$(date +%D_%T) $(basename $TARBALL) done." >>$LOG
done
echo exiting build bot...
