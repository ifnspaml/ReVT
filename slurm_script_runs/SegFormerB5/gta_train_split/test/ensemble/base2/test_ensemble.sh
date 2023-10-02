#!/bin/bash

##GENERAL -----
#SBATCH --cpus-per-task=2
#SBATCH --gres=gpu
#SBATCH --mem=32000M
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=1

##DEBUG -----
##SBATCH --partition=debug
##SBATCH --time=00:20:00

##NORMAL -----
#SBATCH --partition=gpu,gpub
#SBATCH --time=7-00:00:00
##SBATCH --exclude=gpu[04,02,05,01]

######################################################################################
### Parameters:

## Name of the job script
#SBATCH --job-name=SegFormer_B5_gta-trainset_base_ensemble_2_abc

## Name of the log file
#SBATCH --output=train_abc-%j.out

## The config that is used for training and testing
main_config="./local_configs/segformer/B5/segformer.b5.512x512.gta2cs.40k.batch2.py"

## The name of the working dir where the results are saved. at the end the prefix "_[a..z]" is added.
declare -a work_dirs=("./work_dirs/gta_train_split/segformer.b5.512x512.gta2cs.40k.batch2_base_a/latest.pth"
                      "./work_dirs/gta_train_split/segformer.b5.512x512.gta2cs.40k.batch2_base_b/latest.pth"
                      "./work_dirs/gta_train_split/segformer.b5.512x512.gta2cs.40k.batch2_base_c/latest.pth"
                      "./work_dirs/gta_train_split/segformer.b5.512x512.gta2cs.40k.batch2_base_d/latest.pth"
                      "./work_dirs/gta_train_split/segformer.b5.512x512.gta2cs.40k.batch2_base_e/latest.pth"
                      "./work_dirs/gta_train_split/segformer.b5.512x512.gta2cs.40k.batch2_base_f/latest.pth"
                      "./work_dirs/gta_train_split/segformer.b5.512x512.gta2cs.40k.batch2_base_g/latest.pth"
                      "./work_dirs/gta_train_split/segformer.b5.512x512.gta2cs.40k.batch2_base_h/latest.pth")

declare -a ensemble_orders=("0;1" "0;2" "1;2")

## Defines the starting value for the working dir prefix
work_dir_start_char="a"

## Defines the target domains on which the models are evaluated after training
test_cityscapes=false
test_cityscapes_val=true
test_bdd=false
test_mapillary=false
test_acdc=false
test_kitti=false
test_synthia=false
test_gta_val=false
test_synthia_val=false

######################################################################################

# Load modules
module load comp/gcc/11.2.0
source activate transformer-domain-generalization

# Extra output
nvidia-smi
echo -e "Node: $(hostname)"
echo -e "Job internal GPU id(s): $CUDA_VISIBLE_DEVICES"
echo -e "Job external GPU id(s): ${SLURM_JOB_GPUS}"

# create work_dirs names and seeds

suffix=$(printf '%x\n' "'$work_dir_start_char")


# Define variables for Test dataset
declare -a dataset_names=()
declare -a dataset_types=()
declare -a dataset_data_root=()
declare -a dataset_img_dir=()
declare -a dataset_ann_dir=()
declare -a data_test_split=()

if [ "$test_cityscapes" = true ] ; then
    dataset_names+=("Cityscapes")
    dataset_types+=("CityscapesDataset")
    dataset_data_root+=("data/cityscapes/")
    dataset_img_dir+=("leftImg8bit/val")
    dataset_ann_dir+=("gtFine/val")
    data_test_split+=("")
fi
if [ "$test_cityscapes_val" = true ] ; then
    dataset_names+=("Cityscapes_val")
    dataset_types+=("CityscapesDataset")
    dataset_data_root+=("data/")
    dataset_img_dir+=("cityscapes/leftImg8bit/train")
    dataset_ann_dir+=("cityscapes/gtFine/train")
    data_test_split+=("data.test.split=\"cs_splits/val_split.txt\"")
fi
if [ "$test_bdd" = true ] ; then
    dataset_names+=("bdd")
    dataset_types+=("BDD100kDataset")
    dataset_data_root+=("data/bdd100k/")
    dataset_img_dir+=("images/val")
    dataset_ann_dir+=("labels/val")
    data_test_split+=("")
fi
if [ "$test_mapillary" = true ] ; then
    dataset_names+=("mapillary")
    dataset_types+=("MapillaryDataset")
    dataset_data_root+=("data/mapillary/")
    dataset_img_dir+=("validation/ColorImage")
    dataset_ann_dir+=("segmentation_trainid/validation/Segmentation")
    data_test_split+=("")
fi
if [ "$test_acdc" = true ] ; then
    dataset_names+=("acdc")
    dataset_types+=("ACDCDataset")
    dataset_data_root+=("data/acdc/")
    dataset_img_dir+=("rgb_anon/val")
    dataset_ann_dir+=("gt/val")
    data_test_split+=("")
fi
if [ "$test_kitti" = true ] ; then
    dataset_names+=("kitti")
    dataset_types+=("KITTI2015Dataset")
    dataset_data_root+=("data/kitti/")
    dataset_img_dir+=("images/validation")
    dataset_ann_dir+=("labels/validation")
    data_test_split+=("")
fi
if [ "$test_synthia" = true ] ; then
    dataset_names+=("synthia")
    dataset_types+=("SynthiaDataset")
    dataset_data_root+=("data/synthia/")
    dataset_img_dir+=("RGB")
    dataset_ann_dir+=("GT/LABELS/LABELS")
    data_test_split+=("")
fi
if [ "$test_gta_val" = true ] ; then
    dataset_names+=("gta_val")
    dataset_types+=("GTADataset")
    dataset_data_root+=("data/")
    dataset_img_dir+=("gta/images")
    dataset_ann_dir+=("gta/labels")

    data_test_split+=("data.test.split=\"gta_splits/val_split.txt\"")
fi
if [ "$test_synthia_val" = true ] ; then
    dataset_names+=("synthia_val")
    dataset_types+=("SynthiaDataset")
    dataset_data_root+=("data/")
    dataset_img_dir+=("synthia/RGB")
    dataset_ann_dir+=("synthia/GT/LABELS/LABELS")
    data_test_split+=("data.test.split=\"synthia_splits/val_split.txt\"")
fi
echo -e "Test Datasets:"
for dataset_idx in "${!dataset_names[@]}"; do
    echo -e "   ${dataset_names[dataset_idx]}"
done

# Execute programs
script_dir=$(pwd)
cd ~/work/transformer-domain-generalization || return

# delete all files in the tmp_files dir that are older than 2d
find ./tmp_files -name '*.*' -mmin +3000 -delete

for checkpoint_idx in "${!ensemble_orders[@]}"; do
  IFS=";" read -r -a order <<< "${ensemble_orders[checkpoint_idx]}"
  checkpoints_str=""
  for j in "${!order[@]}"; do
      checkpoints_str+=" ${work_dirs["${order[j]}"]}"
  done


  for dataset_idx in "${!dataset_names[@]}"; do
    echo -e "Test on ${dataset_names[dataset_idx]}"
    letter=$(echo "$((suffix + checkpoint_idx))" | xxd -p -r)
    log_file="${script_dir}/test_${letter}_on_${dataset_names[dataset_idx]}.log"
    isInFile=$( (cat "${log_file}" || true) | grep -c "mIoU")
    if [ $isInFile -eq 0 ]; then
        echo -e "Test all on ${dataset_names[dataset_idx]}" >> "${log_file}"
        echo -e "Test for ${checkpoint_idx}:"
        echo -e "Test for ${checkpoint_idx}:" >> "${log_file}"
        srun --output "${log_file}"\
         python ./tools/test_ensemble.py\
         "${main_config}"\
         $(echo -n "$checkpoints_str")\
         --gpu-collect\
         --eval-options efficient_test='True'\
         --no-progress-bar\
         --options \
            data.test.type="${dataset_types[dataset_idx]}"\
            dataset_type="${dataset_types[dataset_idx]}"\
            data_root="${dataset_data_root[dataset_idx]}"\
            data.test.data_root="${dataset_data_root[dataset_idx]}"\
            data.test.img_dir="${dataset_img_dir[dataset_idx]}"\
            data.test.ann_dir="${dataset_ann_dir[dataset_idx]}"\
            $(echo -n "${data_test_split[dataset_idx]}")
        echo -e "___________________________________________________"
    fi
  done
done