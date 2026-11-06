-- ====================================================================
-- MedTrack Medical Records Manager - Complete MySQL Database Schema
-- Compatible with MySQL 5.7+ and MySQL 8.0+
-- ====================================================================

CREATE DATABASE IF NOT EXISTS `meditrack` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `meditrack`;

-- Disable foreign key checks during initialization
SET FOREIGN_KEY_CHECKS = 0;

-- 1. Users Table (Authentication & Accounts)
DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
    `id` VARCHAR(64) NOT NULL,
    `name` VARCHAR(150) NOT NULL,
    `email` VARCHAR(150) NOT NULL,
    `password_hash` VARCHAR(255) NOT NULL,
    `role` ENUM('Patient', 'Doctor', 'Admin') NOT NULL DEFAULT 'Patient',
    `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_users_email` (`email`),
    INDEX `idx_users_role` (`role`),
    INDEX `idx_users_active` (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Patient Profiles Table
DROP TABLE IF EXISTS `patient_profiles`;
CREATE TABLE `patient_profiles` (
    `patient_id` VARCHAR(64) NOT NULL,
    `age` INT NULL,
    `gender` VARCHAR(20) NULL,
    `blood_group` VARCHAR(10) NULL,
    `contact_number` VARCHAR(30) NULL,
    `emergency_contact` VARCHAR(30) NULL,
    `allergies` TEXT NULL,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`patient_id`),
    CONSTRAINT `fk_patient_profiles_user` FOREIGN KEY (`patient_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Medical Records Table (Medical History Visits)
DROP TABLE IF EXISTS `medical_records`;
CREATE TABLE `medical_records` (
    `record_id` VARCHAR(64) NOT NULL,
    `patient_id` VARCHAR(64) NOT NULL,
    `doctor_or_hospital` VARCHAR(200) NOT NULL,
    `visit_date` DATETIME NOT NULL,
    `reason` VARCHAR(255) NOT NULL,
    `diagnosis` TEXT NOT NULL,
    `prescription` TEXT NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`record_id`),
    INDEX `idx_records_patient` (`patient_id`),
    INDEX `idx_records_visit_date` (`visit_date`),
    CONSTRAINT `fk_records_patient` FOREIGN KEY (`patient_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Doctor-Patient Access Grants Table (Sharing Permissions)
DROP TABLE IF EXISTS `doctor_patient_access`;
CREATE TABLE `doctor_patient_access` (
    `id` INT AUTO_INCREMENT NOT NULL,
    `patient_id` VARCHAR(64) NOT NULL,
    `doctor_id` VARCHAR(64) NOT NULL,
    `granted_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_patient_doctor` (`patient_id`, `doctor_id`),
    INDEX `idx_access_patient` (`patient_id`),
    INDEX `idx_access_doctor` (`doctor_id`),
    CONSTRAINT `fk_access_patient` FOREIGN KEY (`patient_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_access_doctor` FOREIGN KEY (`doctor_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Medical Reports Table (Smart Medical Report Management)
DROP TABLE IF EXISTS `medical_reports`;
CREATE TABLE `medical_reports` (
    `report_id` VARCHAR(36) NOT NULL,
    `patient_id` VARCHAR(64) NOT NULL,
    `medical_record_id` VARCHAR(64) NULL,
    `report_title` VARCHAR(255) NOT NULL,
    `report_category` VARCHAR(100) NOT NULL,
    `doctor_name` VARCHAR(150) NOT NULL DEFAULT '',
    `hospital_name` VARCHAR(150) NOT NULL DEFAULT '',
    `report_date` DATETIME NOT NULL,
    `file_name` VARCHAR(255) NOT NULL,
    `file_path` VARCHAR(500) NOT NULL,
    `file_type` VARCHAR(20) NOT NULL,
    `description` TEXT NOT NULL,
    `uploaded_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`report_id`),
    INDEX `idx_reports_patient` (`patient_id`),
    INDEX `idx_reports_record` (`medical_record_id`),
    INDEX `idx_reports_category` (`report_category`),
    INDEX `idx_reports_date` (`report_date`),
    INDEX `idx_reports_title` (`report_title`),
    INDEX `idx_reports_uploaded` (`uploaded_at`),
    CONSTRAINT `fk_reports_patient` FOREIGN KEY (`patient_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_reports_record` FOREIGN KEY (`medical_record_id`) REFERENCES `medical_records` (`record_id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
