#Prepare workspace:
rm(list = ls())
library(haven)
library(readr)
library(dplyr)
library(lubridate)
library(writexl)
library(stringr)

#Set working directory:
wd <- "/Users/lillykirby/Documents/GitHub/Portfolio/Patent Data Cleaning & Restructuring (R)"
setwd(wd)

#Import old data:
FDA_drug_patents <- read_dta("Raw Data/1984 - 2016 clean_tables_stata/4_clean_tables_stata/FDA_drug_patents.dta")

#Import new data:
patent16 <- read_delim("Raw Data/New OB Data/2016.08.01 OB Wayback/2016.08.01 OB Wayback/patent.txt", 
                       delim = "~", escape_double = FALSE, col_types = cols(Delist_Flag = col_character()), 
                       trim_ws = TRUE)
patent16$edition <- 2016

patent17 <- read_delim("Raw Data/New OB Data/2017.01.11 OB Wayback/2017.01.11 OB Wayback/patent.txt", 
                       delim = "~", escape_double = FALSE, col_types = cols(Delist_Flag = col_character()), 
                       trim_ws = TRUE)
patent17$edition <- 2017

patent18 <- read_delim("Raw Data/New OB Data/2018.01.05 OB Wayback/2018.01.05 OB Wayback/patent.txt", 
                       delim = "~", escape_double = FALSE, trim_ws = TRUE)
patent18$edition <- 2018

patent19 <- read_delim("Raw Data/New OB Data/2019.02.07 OB Wayback/2019.02.07 OB Wayback/patent.txt", 
                       delim = "~", escape_double = FALSE, col_types = cols(Delist_Flag = col_character()), 
                       trim_ws = TRUE)
patent19$edition <- 2019

patent20 <- read_delim("Raw Data/New OB Data/2020.12.20 OB Wayback/2020.12.20 OB Wayback/patent.txt", 
                       delim = "~", escape_double = FALSE, trim_ws = TRUE)
patent20$edition <- 2020

patent21 <- read_delim("Raw Data/New OB Data/2021.10.24 OB Wayback/2021.10.24 OB Wayback/patent.txt", 
                       delim = "~", escape_double = FALSE, trim_ws = TRUE)
patent21$edition <- 2021

patent22 <- read_delim("Raw Data/New OB Data/2022 OB EOBZIP_2022_10/2022 OB EOBZIP_2022_10/patent.txt", 
                       delim = "~", escape_double = FALSE, col_types = cols(Delist_Flag = col_character()), 
                       trim_ws = TRUE)
patent22$edition <- 2022

patent23 <- read_delim("Raw Data/New OB Data/2023 OB EOBZIP_2023_11/2023 OB EOBZIP_2023_11/patent.txt", 
                       delim = "~", escape_double = FALSE, col_types = cols(Delist_Flag = col_character()), 
                       trim_ws = TRUE)
patent23$edition <- 2023

patent24 <- read_delim("Raw Data/New OB Data/2024 OB EOBZIP_2024_02/2024 OB EOBZIP_2024_02/patent.txt", 
                       delim = "~", escape_double = FALSE, col_types = cols(Delist_Flag = col_character()), 
                       trim_ws = TRUE)
patent24$edition <-2024

#Rename variables:
names1 <- c("application_type", "application_number", "product_number", "patent_number", 
            "patent_expiration", "DS", "DP", "use_code", "delist_requested", "edition")
names(patent16) <- names1
names(patent17) <- names1

names2 <- c("application_type", "application_number", "product_number", "patent_number", 
            "patent_expiration", "DS", "DP", "use_code", "delist_requested", "submission_date", "edition")
names(patent18) <- names2
names(patent19) <- names2
names(patent20) <- names2
names(patent21) <- names2
names(patent22) <- names2
names(patent23) <- names2
names(patent24) <- names2

#Reformat date variables:
FDA_drug_patents$patent_expiration = format(FDA_drug_patents$patent_expiration, "%b %d, %Y")
FDA_drug_patents$patent_expiration <- as.character(FDA_drug_patents$patent_expiration)

#Append to 1984 - 2016 OB data:
updated_FDA_drug_patents <- bind_rows(FDA_drug_patents, patent16, patent17, patent18,
                                      patent19, patent20, patent21, patent22, patent23,
                                      patent24)

#Recode variables:
updated_FDA_drug_patents$delist_requested <- gsub("Y", "1", updated_FDA_drug_patents$delist_requested)
updated_FDA_drug_patents$delist_requested <- gsub("N/A", "0", updated_FDA_drug_patents$delist_requested)

updated_FDA_drug_patents$DS <- gsub("Y", "1", updated_FDA_drug_patents$DS)
updated_FDA_drug_patents$DS <- gsub("N/A", "0", updated_FDA_drug_patents$DS)

updated_FDA_drug_patents$DP <- gsub("Y", "1", updated_FDA_drug_patents$DP)
updated_FDA_drug_patents$DP <- gsub("N/A", "0", updated_FDA_drug_patents$DP)

table(updated_FDA_drug_patents$delist_requested)
#Should have 129,530 with no delist flag and 1,512 with a delist flag

###############################################################################

#Import product data to merge:
product16 <- read_delim("Raw Data/New OB Data/2016.08.01 OB Wayback/2016.08.01 OB Wayback/products.txt", 
                        delim = "~", escape_double = FALSE, trim_ws = TRUE)
product16$edition <- 2016

product17 <- read_delim("Raw Data/New OB Data/2017.01.11 OB Wayback/2017.01.11 OB Wayback/products.txt", 
                        delim = "~", escape_double = FALSE, trim_ws = TRUE)
product17$edition <- 2017

product18 <- read_delim("Raw Data/New OB Data/2018.01.05 OB Wayback/2018.01.05 OB Wayback/products.txt", 
                        delim = "~", escape_double = FALSE, trim_ws = TRUE)
product18$edition <- 2018

product19 <- read_delim("Raw Data/New OB Data/2019.02.07 OB Wayback/2019.02.07 OB Wayback/products.txt", 
                        delim = "~", escape_double = FALSE, trim_ws = TRUE)
product19$edition <- 2019

product20 <- read_delim("Raw Data/New OB Data/2020.12.20 OB Wayback/2020.12.20 OB Wayback/products.txt", 
                        delim = "~", escape_double = FALSE, trim_ws = TRUE)
product20$edition <- 2020

product21 <- read_delim("Raw Data/New OB Data/2021.10.24 OB Wayback/2021.10.24 OB Wayback/products.txt", 
                        delim = "~", escape_double = FALSE, trim_ws = TRUE)
product21$edition <- 2021

product22 <- read_delim("Raw Data/New OB Data/2022 OB EOBZIP_2022_10/2022 OB EOBZIP_2022_10/products.txt", 
                        delim = "~", escape_double = FALSE, trim_ws = TRUE)
product22$edition <- 2022

product23 <- read_delim("Raw Data/New OB Data/2023 OB EOBZIP_2023_11/2023 OB EOBZIP_2023_11/products.txt", 
                        delim = "~", escape_double = FALSE, trim_ws = TRUE)
product23$edition <- 2023

product24 <- read_delim("Raw Data/New OB Data/2024 OB EOBZIP_2024_02/2024 OB EOBZIP_2024_02/products.txt", 
                        delim = "~", escape_double = FALSE, trim_ws = TRUE)
product24$edition <- 2024

#Rename variables:
names3 <- c("ingredient", "form", "trade", "applicant", "strength", 
            "appl_type", "application_number", "product_number", "te_code",
            "approval_date", "RLD", "type", "applicant_full_name", "edition")
names(product16) <- names3
names(product17) <- names3

names4 <- c("ingredient", "form", "trade", "applicant", "strength", 
            "appl_type", "application_number", "product_number", "te_code",
            "approval_date", "RLD", "RS", "type", "applicant_full_name", "edition")
names(product18) <- names4
names(product19) <- names4
names(product20) <- names4
names(product21) <- names4
names(product22) <- names4
names(product23) <- names4
names(product24) <- names4


#Append product data:
products <- bind_rows(product16, product17, product18, product19, product20, product21,
                      product22, product23, product24)

#Drop unnecessary data for merging:
productmerge <- products
productmerge$type <- NULL
productmerge$edition <- NULL
productmerge$RS <- NULL
productmerge$applicant <- NULL
productmerge$applicant_full_name <- NULL
productmerge$te_code <- NULL
productmerge$RLD <- NULL
productmerge$form <- NULL
productmerge$strength <- NULL

#Reformat date variable for grouping to locate duplicates:
productmerge$approved_before_1982 <- ifelse(productmerge$approval_date == "Approved Prior to Jan 1, 1982",
                                            1, 0)
productmerge$appr_date <- productmerge$approval_date
productmerge$appr_date <- gsub("Approved Prior to Jan 1, 1982", "Jan 1, 1982", productmerge$appr_date)
productmerge$appr_date <- mdy(productmerge$appr_date)

#Arrange by date and drop duplicate observations in terms of app/product number:
productmerge <- arrange(productmerge, appr_date)
productmerge <- unique(productmerge)

productmerge$dupe <- duplicated(productmerge[, c("application_number", "product_number")]) | 
  duplicated(productmerge[, c("application_number", "product_number")])

productmerge <- productmerge[productmerge$dupe != TRUE,]
productmerge$dupe <- NULL


#Merge patent and product data:
patentproduct <- left_join(updated_FDA_drug_patents, productmerge, by = c("application_number", 
                                                                          "product_number"))

#Fill in missing data:
patentproduct <- patentproduct %>%
  mutate(active_ingredient = coalesce(active_ingredient, ingredient))
patentproduct <- patentproduct %>%
  mutate(trade_name = coalesce(trade_name, trade))

patentproduct$active_ingredient <- gsub("N/A", patentproduct$ingredient, patentproduct$active_ingredient)
patentproduct$trade_name <- gsub("N/A", patentproduct$trade, patentproduct$trade_name)
patentproduct$application_type <- gsub("N/A", patentproduct$appl_type, patentproduct$application_type)

#Drop duplicates
patentproduct <- unique(patentproduct)

#Assess missing data:
sum(is.na(patentproduct$active_ingredient))
mean(is.na(patentproduct$active_ingredient))

#Clean up data frame for Excel file:
patent_product_clean <- patentproduct
patent_product_clean$appl_type <- NULL
patent_product_clean$appr_date <- NULL
patent_product_clean$ingredient <- NULL
patent_product_clean$trade <- NULL
patent_product_clean$approved_before_1982 <- NULL

#Export master set as Excel file:
write_xlsx(patent_product_clean, "patent_product_clean.xlsx")