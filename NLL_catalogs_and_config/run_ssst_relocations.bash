#!/bin/bash

# 20230920 - Anthony Lomax, ALomax Scientific

# script to run NLLoc and Loc2ssst iteratively to generate SSST travel-time grids and SSST corrected NLLoc locations

# log output is written to run_ssst_relocations.log


# USER VARIABLES TO EDIT =================================================================

# identifier for a particular run
RUN_NAME=20240704C_SSST

# name used for output directories
PROJECT_NAME=Norcia_2016

# output path (avoid links, using links here can cause problems with shell finding linked files, e.g. travel-time files linked in Loc2ssst)
OUT=/Users/anthony/work_temp/nlloc_tmp/${PROJECT_NAME}

# catalog run name used for arrival observations in NLLOC_OBS format
#    picks for ssst corrections (e.g. higher M, fewer events)
#    picks for final NLLoc locations (full set of events)
##CATALOG=Norcia_2016_20160815-20170815_M2.0_ingv
##CATALOG_FINAL=Norcia_2016_20160815-20170815_M1.7
##PHASEFILE_EXT="nlloc_obs"
#
# 20240228A_SSST 20240304A_SSST
#CATALOG=Norcia_2016_20161020-1130_ingv
#CATALOG_FINAL=Norcia_2016_20161020-1130_ingv
#PHASEFILE_EXT="nlloc_obs"
#
# Spina PhaseNet
###CATALOG=Norcia_Spina_DB15_20161020-1130_SUBSET
###CATALOG_FINAL=Norcia_Spina_DB15_20161020-1130_SUBSET
###PHASEFILE_EXT="phs"
#
# INGV manual Oct30
##CATALOG=Norcia_2016_20161030_ingv
##CATALOG_FINAL=Norcia_2016_20161030_ingv
##PHASEFILE_EXT="nlloc_obs"
#
# Spina 20240304 INGV events only
# 20240304B_SSST 
####CATALOG=Norcia_INGV_Spina_PN_INSTANCE_005
####CATALOG_FINAL=${CATALOG}
####PHASEFILE_EXT="phs"
#
# Spina 20240626
PHASEFILE_EXT="phs"
##CATALOG=NEW_INGV ; CATALOG_FINAL=${CATALOG}
##CATALOG=NEW_PN_ORIG28 ; CATALOG_FINAL=${CATALOG}
CATALOG=NEW_PN_INSTANCE28 ; CATALOG_FINAL=${CATALOG}

SSST_CONTROL_FILE=Norcia_2016_Loc2ssst.in

# model identifier name
MODEL=Tan2021_smooth
CONTROL_FILE=Norcia_2016_Tan2021_smooth.in
VPVS=-9.99
#VPVS=1.84   # VpVs.xlsx

# variables that set SSST spatial smoothing width D
# starting D, divisor for next D, minimum D (km)
declare -i CHAR_DIST_INIT=9999	# initial dist is huge -> static corrections
declare -i CHAR_DIST_START=16   # starting finite dist is ~ 1/2 to 1 X size of target seismicity
declare -i CHAR_DIST_DIVISOR=2  # usually 2
declare -i CHAR_DIST_MIN=2      # allows repeated SSST calculations for smallest dist, if enough iterations
CHAR_DIST_SCALE=1 	# default
#CHAR_DIST_SCALE=10 	# allows decimal char dist values (e.g. < 1), char dist passed to Loc2ssst is CHAR_DIST/CHAR_DIST_SCALE


# variables set from above, edit if necessary
LOC_OBS="nlloc/${CATALOG}/*.${PHASEFILE_EXT}"
SSST_MODEL_NAME=${PROJECT_NAME}_${MODEL}_SSST
# initial, NLL time-grids, as in CONTROL_FILE 
INIT_TIME_ROOT=${OUT}/20231110/${MODEL}/time/${MODEL}

# sets min number of phases required to relocate an event and use for SSST before final location, for final location = 4
# should be same as Loc2ssst -> LSPHSTAT NRdgs_Min
MIN_NUM_PHASES_LOC=24  # *_Loc2ssst.in

# sets that NLLoc oct-tree grids and fmamp output are NOT saved before final iteration
# !! IMPORTANT: CONTROL_FILE should not contain SAVE_NLLOC_OCTREE or SAVE_FMAMP in LOCHYPOUT statement 
SAVE_NLLOC_OCTREE=""
SAVE_FMAMP=""
# uncomment the following line to use location results before final iteration for NLL-coherence (requires oct-tree grids)
#SAVE_NLLOC_OCTREE="SAVE_NLLOC_OCTREE"
# uncomment the following line to use location results before final iteration for fmamp first-motion focal mechanism calculation
#SAVE_FMAMP="SAVE_FMAMP"

SV_CMD="java net.alomax.seismicity.Seismicity"

# verify also NUM_CORES below
# verify also ITERATION_MAX below

# END - USER VARIABLES TO EDIT =================================================================



# command line arguments
echo "Usage: $0 [iteration_start iteration_max char_dist]"
echo " iteration_start default 0"
echo " iteration_max default 3"
echo "Example:"
echo "$0"
echo "$0 3 5 8"
echo "$0 0 -1 9999  # only run initial locations"

 
 
mkdir -p ${OUT}/${RUN_NAME}
cp -p $0 ${OUT}/${RUN_NAME}
cp -p ${CONTROL_FILE} ${OUT}/${RUN_NAME}
cp -p ${SSST_CONTROL_FILE} ${OUT}/${RUN_NAME}
mkdir tmp
 
cat << END > run_ssst_relocations.log
${PROJECT_NAME}/${RUN_NAME}/${SSST_MODEL_NAME} ${CATALOG}
END

# NLLoc control file for cluster posterior location
SKELETON_CONF=tmp/NLL.cluster_SKELETON_SSST.conf
# comment out INCLUDE, LOCFILES and LOCMETH in original loc control file and output to SKELETON_CONF
sed '/INCLUDE/ s/^#*/#/' ${CONTROL_FILE} > tmp/temp1.conf
sed '/LOCFILES/ s/^#*/#/' tmp/temp1.conf > tmp/temp2.conf
sed '/LOCMETH/ s/^#*/#/' tmp/temp2.conf > ${SKELETON_CONF}


declare -i ITERATION
declare -i ITERATION_MAX

# first run uses special initial size
declare -i CHAR_DIST=${CHAR_DIST_INIT}

TIME_ROOT=${INIT_TIME_ROOT}
if [ -z "$1" ]; then
	ITERATION=0
	ITERATION_MAX=4
elif [ -z "$3" ]; then
	echo "ERROR: need 0 or 3 arguments."
	exit
else
	ITERATION=$1
	ITERATION_MAX=$2
	if [ $((${ITERATION} > 0)) = 1 ]; then
		declare -i LAST_TIME_ROOT_ITERATION=ITERATION-1
		TIME_ROOT=${OUT}/${RUN_NAME}/${SSST_MODEL_NAME}/ssst_corr${LAST_TIME_ROOT_ITERATION}/${CATALOG}/${MODEL}
		VPVS=-9.99
	fi
	CHAR_DIST="$3"
fi

declare -i ITERATION_FINAL=ITERATION_MAX+1
while [ $((${ITERATION} <= ${ITERATION_FINAL})) = 1 ]; do

	CHAR_DIST_USE=$(echo "scale=3; ${CHAR_DIST}/${CHAR_DIST_SCALE}" | bc)

	echo "Start iteration ${ITERATION}/${ITERATION_MAX} ================================="
	cat << END >> run_ssst_relocations.log
Start iteration ${ITERATION}/${ITERATION_MAX} =================================
END

	echo "Running NLLoc for iteration ${ITERATION}/${ITERATION_MAX}..."

	OUT_ROOT=${OUT}/${RUN_NAME}/${SSST_MODEL_NAME}/loc_ssst_corr${ITERATION}/${CATALOG}
	if [ $((${ITERATION} == ${ITERATION_FINAL})) = 1 ]; then
		OUT_ROOT=${OUT}/${RUN_NAME}/${SSST_MODEL_NAME}/loc_ssst_corr${ITERATION}/${CATALOG_FINAL}
		LOC_OBS="nlloc/${CATALOG_FINAL}/*.${PHASEFILE_EXT}"
		SAVE_NLLOC_OCTREE="SAVE_NLLOC_OCTREE"
		SAVE_FMAMP="SAVE_FMAMP"
		MIN_NUM_PHASES_LOC=4  # Loc2ssst is no longer run, use all or most events for final NLLoc locations
	fi

	# ----------------------------------------------------------------
	# run NLLoc in parallel

	mkdir -p ${OUT_ROOT}

	cat << END >> run_ssst_relocations.log
    Running NLLoc:
${SV_CMD} ${OUT_ROOT}/${PROJECT_NAME}*sum*hyp &
END

	CONTROL_FILE_TMP=tmp/${PROJECT_NAME}_nll_${ITERATION}.in
	cp ${SKELETON_CONF} ${CONTROL_FILE_TMP}

	# specify the number NLLoc to be run in parallel (e.g. up to the number of physical CPU cores available)
	NUM_CORES=14
	# get a list of all obs files
	OBS_LIST=$(echo ${LOC_OBS})
	for ENTRY in ${OBS_LIST}; do
		echo "${ENTRY}"
	done  > tmp/obs.txt
	# count the total number of obs files
	COUNT=$(wc -l < tmp/obs.txt) 
	rm -r tmp/obs_*
	rm -r tmp/obsfiles_*
	# split obs file list into NUM_CORES sub-lists
	echo "split -l $((1 + ${COUNT} / ${NUM_CORES})) tmp/obs.txt tmp/obs_"
	split -l $((1 + ${COUNT} / ${NUM_CORES})) tmp/obs.txt tmp/obs_
	# produces temp/obs_aa, temp/obs_ab, etc
	# run NLLoc for each sub-list
	declare -i INDEX=0
	for SPLIT_OBS_FILE in tmp/obs_* ; do
		echo "Running: ${INDEX} ${SPLIT_OBS_FILE}"
		cp ${CONTROL_FILE_TMP} ${CONTROL_FILE_TMP}_${INDEX}
		# copy obs files in sub-list to temp obs file directory
		mkdir tmp/obsfiles_${INDEX}
		{
			while read OFILE; do
				cp -p ${OFILE} tmp/obsfiles_${INDEX}
			done
		} < ${SPLIT_OBS_FILE}
		cat << END >> ${CONTROL_FILE_TMP}_${INDEX}
#
# added by run_ssst_relocations.bash
CONTROL 0 54321
LOCCOM ${RUN_NAME} ${SSST_MODEL_NAME} loc_ssst_corr${ITERATION}
LOCFILES tmp/obsfiles_${INDEX}/*.${PHASEFILE_EXT} NLLOC_OBS  ${TIME_ROOT}  ${OUT_ROOT}_${INDEX}/${PROJECT_NAME}  0
LOCMETH EDT_OT_WT 9999.0 ${MIN_NUM_PHASES_LOC} -1 -1 ${VPVS} -1 -1 1
LOCHYPOUT SAVE_NLLOC_ALL  NLL_FORMAT_VER_2  ${SAVE_NLLOC_OCTREE} ${SAVE_FMAMP}
END
		mkdir -p ${OUT_ROOT}_${INDEX}
		NLLoc ${CONTROL_FILE_TMP}_${INDEX} &
		PIDS[${INDEX}]=$!
		INDEX=INDEX+1
	done
	# wait for all PIDS
	for PID in ${PIDS[*]}; do
		wait $PID
		status=$?
		echo "Finished: PID=${PID} status=${status} ================================="
	done
	# assemble unique NLL output
	cp -a ${OUT_ROOT}_*/. ${OUT_ROOT}/
	cat ${OUT_ROOT}_*/${PROJECT_NAME}.sum.grid0.loc.hyp > ${OUT_ROOT}/${PROJECT_NAME}.sum.grid0.loc.hyp
	echo "" > ${OUT_ROOT}/WARNING.concatenated_output_of_multiple_NLLoc_runs.WARNING
	cat ${OUT_ROOT}_*/${PROJECT_NAME}.sum.grid0.loc.stations > ${OUT_ROOT}/${PROJECT_NAME}.sum.grid0.loc.stations

	# END run NLLoc in parallel
	# ----------------------------------------------------------------

	if [ $((${ITERATION} == ${ITERATION_FINAL})) = 1 ]; then
		break
	fi

	echo ""
	echo ""
	echo "Running Loc2ssst for iteration ${ITERATION}/${ITERATION_MAX}  CharDist=${CHAR_DIST_USE} ================================="

	LS_OUT_ROOT=${OUT}/${RUN_NAME}/${SSST_MODEL_NAME}/ssst_corr${ITERATION}/${CATALOG}
	mkdir -p ${LS_OUT_ROOT}

	# link all previous travel-time files to Loc2ssst output so will be present for any sta-phase not processed by Loc2ssst
	ln -s ${TIME_ROOT}*.time.* ${LS_OUT_ROOT}		# file root assumed same as INIT_TIME_ROOT file root!

	LS_OUT_ROOT=${LS_OUT_ROOT}/${MODEL}

	cat << END >> run_ssst_relocations.log
    Running Loc2ssst  CharDist=${CHAR_DIST_USE} ${LS_OUT_ROOT}
END

	SSST_CONTROL_FILE_TMP=tmp/${PROJECT_NAME}_ssst_${ITERATION}.in
	cp ${SSST_CONTROL_FILE} ${SSST_CONTROL_FILE_TMP}
	LSMODE="LSMODE ANGLES_NO"
	if [ $((${ITERATION} == ${ITERATION_MAX})) = 1 ]; then
		LSMODE="LSMODE ANGLES_YES"
	fi
	cat << END >> ${SSST_CONTROL_FILE_TMP}
LSPARAMS ${CHAR_DIST_USE} 0.0000001
${LSMODE}
LSOUT ${LS_OUT_ROOT}
LSLOCFILES ${OUT_ROOT}/${PROJECT_NAME}.*.*.grid0.loc.hyp
LOCFILES ${LOC_OBS} NLLOC_OBS  ${TIME_ROOT}  ${OUT_ROOT}/${PROJECT_NAME}  0
LOCMETH EDT_OT_WT 9999.0 ${MIN_NUM_PHASES_LOC} -1 -1 ${VPVS} -1 -1 1
END
	./run_ssst.bash ${SSST_CONTROL_FILE_TMP}

	# determined by LSOUT
	TIME_ROOT=${LS_OUT_ROOT}

	echo ""
	echo ""
	echo "Finished iteration ${ITERATION}/${ITERATION_MAX} ================================="
	echo ""
	echo ""

	ITERATION=ITERATION+1
	VPVS=-9.99

	if [ $((${CHAR_DIST} == ${CHAR_DIST_INIT})) = 1 ]; then
		CHAR_DIST=${CHAR_DIST_START}
	elif [ $((${CHAR_DIST} > ${CHAR_DIST_MIN})) = 1 ]; then
		CHAR_DIST=CHAR_DIST/CHAR_DIST_DIVISOR
	fi

done



# write cleanup commands to log
cat << END >> run_ssst_relocations.log

# cleanup commands
# WARNING: the following assume 3 iterations and ssst_corr3 is used for definitive locations and later coherence processing.
rm -r ${OUT}/${RUN_NAME}/${SSST_MODEL_NAME}/ssst_corr[012]
rm -r ${OUT}/${RUN_NAME}/${SSST_MODEL_NAME}/loc_ssst_corr[123]
END

cp -p run_ssst_relocations.log ${OUT}/${RUN_NAME}

# cleanup
rm -r ${OUT_ROOT}_?
rm -r ${OUT_ROOT}_??


cat >> ssst.list << END
${OUT_ROOT}/${PROJECT_NAME}.sum.grid0.loc.hyp
END
