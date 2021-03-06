#How to use RPMM for classification of PTSD status

library(glmnet)
library('CpGassoc')
library(minfi)
library(superpc)
library(isva)
library(RPMM)

#get number of rows in file (reads file faster)
nr <- as.numeric(system('wc -l cleaned_v3a.methylation | awk \'{print $1}\' ',intern=T))

#get list of numeric column classes (reads file faster)
dat_temp <- read.table("cleaned_v3a.methylation", header=T,nrows=50)
classes_to_use <- sapply(dat_temp , class)

#read file
dat0 <- read.table("cleaned_v3a.methylation", header=T,nrows=nr,colClasses=classes_to_use)

############# load in the other stuff like cross hybridizing probes or whatever #########
snp_probes <- read.table('PCA/cpgs_within_10bp_of_SNP.table', header=F,stringsAsFactors=F)
names(snp_probes)[1] <- "CpG"

cross_hybridizing <- read.table('PCA/cpg-non-specific-probes-Illumina450k.txt',header=T,stringsAsFactors=F)
names(cross_hybridizing)[1] <- "CpG"

badprobes <- c(snp_probes$CpG, cross_hybridizing$CpG)

dat <- dat0[-which(row.names(dat0) %in% badprobes),]

#make a dataframe of subject names that goes in the order they appear in the file
dat_order <- as.data.frame(names(dat))

#name the subjects the same as found in the matching column in the batch file
names(dat_order) <- c('methylome_id_fixed')

#establish a note of what the ordering is
dat_order$order <- c(1:(dim(dat)[2]))

batch <- read.csv("data_analysis/demo2_wholedata_methylation_x3c.csv", header=T,na.strings=c("NA","#N/A","N/A"))

#merge batch data with subject name order data
covariates_ordered0 <- merge(batch,dat_order,by='methylome_id_fixed')


#sort the data by order so the phenotype now lines up
covariates_ordered <- covariates_ordered0[order(covariates_ordered0$order),]

#read in studymax covariate data, to get the studymax ids (if doing studymax)
covars_studymax <- read.csv('data_analysis/demo2_studymaxnov0_methylation_x1.csv',header=T,na.strings=c("NA","#N/A","N/A"),stringsAsFactors=F)

##### load in probe annotations #####
probe_annotations <- read.csv('misc/humanmethylation450_15017482_v1-2.csv',header=T,skip=7,stringsAsFactors=F)

##### order this file by the probe order in the data #####
all_qced_probes <- data.frame(row.names(dat))
names(all_qced_probes)[1] <- "IlmnID"
all_qced_probes$order <- 1:dim(all_qced_probes)[1]
merged_probe_types0 <- merge(all_qced_probes,probe_annotations,by="IlmnID",all.x=TRUE)
probe_annotations_use <- merged_probe_types0[order(merged_probe_types0$order),]

n_shelf <- probe_annotations_use[probe_annotations_use$Relation_to_UCSC_CpG_Island == "N_Shelf",]$IlmnID
n_shore <- probe_annotations_use[probe_annotations_use$Relation_to_UCSC_CpG_Island == "N_Shore",]$IlmnID
island <- probe_annotations_use[probe_annotations_use$Relation_to_UCSC_CpG_Island == "Island",]$IlmnID
opensea <- probe_annotations_use[is.na(probe_annotations_use$Relation_to_UCSC_CpG_Island),]$IlmnID
s_shelf <- probe_annotations_use[probe_annotations_use$Relation_to_UCSC_CpG_Island == "S_Shelf",]$IlmnID
s_shore <- probe_annotations_use[probe_annotations_use$Relation_to_UCSC_CpG_Island == "S_Shore",]$IlmnID

#the gene grouping stuff depends on what gene it annotates to, i'll just take the first piece
unlist_split <- function(x, ...)
{
	toret <- unlist(strsplit(x, ...) )[1]
	return(t(toret))
}


probe_annotations_use$UCSC_RefGene_Group_simple <-  sapply(probe_annotations_use$UCSC_RefGene_Group, unlist_split, split = c(";"))

f_utr <- probe_annotations_use[probe_annotations_use$UCSC_RefGene_Group_simple == "5'UTR",]$IlmnID
t_utr <- probe_annotations_use[probe_annotations_use$UCSC_RefGene_Group_simple == "3'UTR",]$IlmnID
tss1500 <-  probe_annotations_use[probe_annotations_use$UCSC_RefGene_Group_simple == "TSS1500",]$IlmnID
tss200 <-  probe_annotations_use[probe_annotations_use$UCSC_RefGene_Group_simple == "TSS200",]$IlmnID
body  <-  probe_annotations_use[probe_annotations_use$UCSC_RefGene_Group_simple == "Body",]$IlmnID
exon  <-  probe_annotations_use[probe_annotations_use$UCSC_RefGene_Group_simple == "1stExon",]$IlmnID
intergenic  <-  probe_annotations_use[is.na(probe_annotations_use$UCSC_RefGene_Group_simple),]$IlmnID

###################### 6 mo analysis in all subjects
covariates_ordered_subset <- subset(covariates_ordered, visit == 3) #& (PTSDbroad == 1 | PTSDbroad_highest == 0))
dat_subset0 <- dat[, names(dat) %in% covariates_ordered_subset$methylome_id_fixed]
covs <- subset(covariates_ordered_subset, select=c(age_v0, CD8T,CD4T,NK,Bcell,Mono ,PC1_HGDP,PC2_HGDP,PC3_HGDP))

##### impute missing data to row median #####
impute_median <- function(x)
{
	med <- median(x,na.rm=T)
	x[is.na(x)] <- med
	return(x)
}

dat_subset <- t(apply(dat_subset0, 1, impute_median))

#Work with M-values
dat_subset <- logit2(dat_subset)


#List of other confounding/variance explaining variables
cpreds_subset <- list (pred1=covariates_ordered_subset$age_v0, pred2=covariates_ordered_subset$CD8T,pred3=covariates_ordered_subset$CD4T,
				pred4=covariates_ordered_subset$NK, pred5=covariates_ordered_subset$Bcell,pred6=covariates_ordered_subset$Mono,
				pred7=covariates_ordered_subset$PC1_HGDP, pred8=covariates_ordered_subset$PC2_HGDP,pred9=covariates_ordered_subset$PC3_HGDP)

#Take the models residualized for covariates via regression
dat_subset_decor <- superpc.decorrelate (dat_subset, cpreds_subset)

covariates_ordered_subset$PTSDbroad

#Load RPMM
source('rpmmtree.R')

#lets make sure it works on the defaults
treetest <- glcTree(dat_subset_decor$res[,1:10000])

#plotImage.RPMMTree(treetest3) #Show RPMM plot
classed <- cbind(row.names(dat_use),RPMMTreeLeafMatrix(treetest3))
colnames(classed)[1] <- "methylome_id_fixed"

covs_classed <- merge(classed,covars_use,by= "methylome_id_fixed")

#Do RPMM class predictions predict PTSD status?
summary(
	glm(rL ~ PTSDbroad , data=covs_classed,family="binomial")
)


