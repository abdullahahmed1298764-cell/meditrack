from datetime import datetime, timezone
import uuid
from database import db

def utc_now():
    return datetime.now(timezone.utc)

class User(db.Model):
    __tablename__ = 'users'

    id = db.Column(db.String(64), primary_key=True)
    name = db.Column(db.String(150), nullable=False)
    email = db.Column(db.String(150), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    role = db.Column(db.String(20), nullable=False)  # 'Patient', 'Doctor', 'Admin'
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    created_at = db.Column(db.DateTime, default=utc_now, nullable=False)

    # Relationships
    records = db.relationship('MedicalRecord', backref='patient', lazy=True, cascade='all, delete-orphan')
    reports = db.relationship('MedicalReport', backref='patient', lazy=True, cascade='all, delete-orphan')

    def to_dict(self):
        return {
            'uid': self.id,
            'id': self.id,
            'name': self.name,
            'email': self.email,
            'role': self.role,
            'isActive': self.is_active,
            'createdAt': self.created_at.isoformat() if self.created_at else None,
        }


class PatientProfile(db.Model):
    __tablename__ = 'patient_profiles'

    patient_id = db.Column(db.String(64), db.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)
    age = db.Column(db.Integer, nullable=True)
    gender = db.Column(db.String(20), nullable=True)
    blood_group = db.Column(db.String(10), nullable=True)
    contact_number = db.Column(db.String(30), nullable=True)
    emergency_contact = db.Column(db.String(30), nullable=True)
    allergies = db.Column(db.Text, nullable=True)
    updated_at = db.Column(db.DateTime, default=utc_now, onupdate=utc_now)

    def to_dict(self):
        return {
            'patientId': self.patient_id,
            'age': self.age,
            'gender': self.gender,
            'bloodGroup': self.blood_group,
            'contactNumber': self.contact_number,
            'emergencyContact': self.emergency_contact,
            'allergies': self.allergies,
            'updatedAt': self.updated_at.isoformat() if self.updated_at else None,
        }


class MedicalRecord(db.Model):
    __tablename__ = 'medical_records'

    record_id = db.Column(db.String(64), primary_key=True)
    patient_id = db.Column(db.String(64), db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    doctor_or_hospital = db.Column(db.String(200), nullable=False)
    visit_date = db.Column(db.DateTime, nullable=False)
    reason = db.Column(db.String(255), nullable=False)
    diagnosis = db.Column(db.Text, nullable=False, default='')
    prescription = db.Column(db.Text, nullable=False, default='')
    created_at = db.Column(db.DateTime, default=utc_now, nullable=False)

    # Relationship to reports
    reports = db.relationship('MedicalReport', backref='medical_record', lazy=True)

    def to_dict(self):
        return {
            'recordId': self.record_id,
            'patientId': self.patient_id,
            'doctorOrHospital': self.doctor_or_hospital,
            'visitDate': self.visit_date.isoformat() if self.visit_date else None,
            'reason': self.reason,
            'diagnosis': self.diagnosis,
            'prescription': self.prescription,
            'createdAt': self.created_at.isoformat() if self.created_at else None,
        }


class DoctorPatientAccess(db.Model):
    __tablename__ = 'doctor_patient_access'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    patient_id = db.Column(db.String(64), db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    doctor_id = db.Column(db.String(64), db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    granted_at = db.Column(db.DateTime, default=utc_now, nullable=False)

    __table_args__ = (
        db.UniqueConstraint('patient_id', 'doctor_id', name='unique_patient_doctor_access'),
    )

    def to_dict(self):
        return {
            'id': self.id,
            'patientId': self.patient_id,
            'doctorId': self.doctor_id,
            'grantedAt': self.granted_at.isoformat() if self.granted_at else None,
        }


class MedicalReport(db.Model):
    __tablename__ = 'medical_reports'

    report_id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    patient_id = db.Column(db.String(64), db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True)
    medical_record_id = db.Column(db.String(64), db.ForeignKey('medical_records.record_id', ondelete='SET NULL'), nullable=True, index=True)
    report_title = db.Column(db.String(255), nullable=False, index=True)
    report_category = db.Column(db.String(100), nullable=False, index=True)
    doctor_name = db.Column(db.String(150), default='', nullable=False)
    hospital_name = db.Column(db.String(150), default='', nullable=False)
    report_date = db.Column(db.DateTime, nullable=False, index=True)
    file_name = db.Column(db.String(255), nullable=False)
    file_path = db.Column(db.String(500), nullable=False)
    file_type = db.Column(db.String(20), nullable=False)
    description = db.Column(db.Text, default='', nullable=False)
    uploaded_at = db.Column(db.DateTime, default=utc_now, nullable=False)

    def to_dict(self):
        return {
            'documentId': self.report_id,
            'reportId': self.report_id,
            'patientId': self.patient_id,
            'recordId': self.medical_record_id or '',
            'medicalRecordId': self.medical_record_id,
            'reportTitle': self.report_title,
            'reportCategory': self.report_category,
            'doctorName': self.doctor_name or '',
            'hospitalName': self.hospital_name or '',
            'reportDate': self.report_date.isoformat() if self.report_date else None,
            'fileName': self.file_name,
            'filePath': self.file_path,
            'fileType': self.file_type.lower(),
            'description': self.description or '',
            'uploadedAt': self.uploaded_at.isoformat() if self.uploaded_at else None,
            'downloadUrl': f"/api/reports/{self.report_id}/download",
        }
