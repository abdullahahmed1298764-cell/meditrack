-- ====================================================================
-- MedTrack Seed Data for Testing & Demonstration
-- Passwords:
--   patient@meditrack.demo: Password123!
--   doctor@meditrack.demo: Password123!
--   admin@meditrack.demo: Admin123!
-- ====================================================================

USE `meditrack`;

-- Demo Users (SHA-256 password hash compatible)
INSERT INTO `users` (`id`, `name`, `email`, `password_hash`, `role`, `is_active`, `created_at`) VALUES
('demo-patient-1', 'John Doe', 'patient@meditrack.demo', '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8', 'Patient', 1, NOW()),
('demo-doctor-1', 'Dr. Sarah Connor', 'doctor@meditrack.demo', '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8', 'Doctor', 1, NOW()),
('demo-admin-1', 'System Administrator', 'admin@meditrack.demo', '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8', 'Admin', 1, NOW())
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- Patient Profile
INSERT INTO `patient_profiles` (`patient_id`, `age`, `gender`, `blood_group`, `contact_number`, `emergency_contact`, `allergies`) VALUES
('demo-patient-1', 32, 'Male', 'O+', '+1-555-0199', '+1-555-0188', 'Penicillin, Dust mites')
ON DUPLICATE KEY UPDATE `age` = VALUES(`age`);

-- Medical History Record
INSERT INTO `medical_records` (`record_id`, `patient_id`, `doctor_or_hospital`, `visit_date`, `reason`, `diagnosis`, `prescription`, `created_at`) VALUES
('rec-demo-001', 'demo-patient-1', 'City General Hospital - Dr. Sarah Connor', '2026-01-15 10:30:00', 'Annual Health Checkup & Chest Pain', 'Mild respiratory congestion and normal cardiovascular exam', 'Azithromycin 500mg once daily for 3 days; Salbutamol inhaler as needed.', NOW())
ON DUPLICATE KEY UPDATE `reason` = VALUES(`reason`);

-- Doctor Access Grant
INSERT INTO `doctor_patient_access` (`patient_id`, `doctor_id`, `granted_at`) VALUES
('demo-patient-1', 'demo-doctor-1', NOW())
ON DUPLICATE KEY UPDATE `granted_at` = VALUES(`granted_at`);
