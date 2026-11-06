-- ====================================================================
-- Migration: Add MedicalReports Table to Existing MySQL Database
-- Compatible with MySQL 5.7+ and MySQL 8.0+
-- ====================================================================

USE `meditrack`;

CREATE TABLE IF NOT EXISTS `medical_reports` (
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
    INDEX `idx_reports_uploaded` (`uploaded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Add foreign key constraints if referenced tables exist
SET @exist_fk_patient = (
    SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'medical_reports'
      AND CONSTRAINT_NAME = 'fk_reports_patient'
);

SET @exist_fk_record = (
    SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'medical_reports'
      AND CONSTRAINT_NAME = 'fk_reports_record'
);

-- Note: In MySQL workbench or CLI, if users table exists:
-- ALTER TABLE `medical_reports` ADD CONSTRAINT `fk_reports_patient` FOREIGN KEY (`patient_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;
-- ALTER TABLE `medical_reports` ADD CONSTRAINT `fk_reports_record` FOREIGN KEY (`medical_record_id`) REFERENCES `medical_records` (`record_id`) ON DELETE SET NULL;
