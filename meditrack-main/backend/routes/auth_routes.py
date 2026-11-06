from datetime import datetime, timezone
import uuid
from flask import Blueprint, request, jsonify
from database import db
from models import User, PatientProfile, DoctorPatientAccess
from auth import hash_password, verify_password, generate_token, token_required, role_required

auth_bp = Blueprint('auth', __name__, url_prefix='/api/auth')

def utc_now():
    return datetime.now(timezone.utc)

@auth_bp.route('/register', methods=['POST'])
def register():
    data = request.get_json() or {}
    name = (data.get('name') or '').strip()
    email = (data.get('email') or '').strip().lower()
    password = (data.get('password') or '').strip()
    role = (data.get('role') or 'Patient').strip()

    if not name or not email or not password:
        return jsonify({'error': 'Name, email, and password are required', 'code': 'VALIDATION_ERROR'}), 400

    if role not in ('Patient', 'Doctor', 'Admin'):
        return jsonify({'error': 'Invalid role. Must be Patient, Doctor, or Admin', 'code': 'INVALID_ROLE'}), 400

    if len(password) < 6:
        return jsonify({'error': 'Password must be at least 6 characters long', 'code': 'WEAK_PASSWORD'}), 400

    if User.query.filter_by(email=email).first():
        return jsonify({'error': 'An account with this email already exists', 'code': 'USER_EXISTS'}), 409

    user_id = data.get('uid') or str(uuid.uuid4())
    hashed = hash_password(password)

    user = User(
        id=user_id,
        name=name,
        email=email,
        password_hash=hashed,
        role=role,
        is_active=True,
        created_at=utc_now()
    )
    db.session.add(user)

    if role == 'Patient':
        profile = PatientProfile(patient_id=user_id)
        db.session.add(profile)

    db.session.commit()

    token = generate_token(user)
    return jsonify({
        'message': 'Account created successfully',
        'token': token,
        'user': user.to_dict()
    }), 201

@auth_bp.route('/login', methods=['POST'])
def login():
    data = request.get_json() or {}
    email = (data.get('email') or '').strip().lower()
    password = (data.get('password') or '').strip()

    if not email or not password:
        return jsonify({'error': 'Email and password are required', 'code': 'VALIDATION_ERROR'}), 400

    user = User.query.filter_by(email=email).first()
    if not user or not verify_password(user.password_hash, password):
        return jsonify({'error': 'Invalid email or password', 'code': 'INVALID_CREDENTIALS'}), 401

    if not user.is_active:
        return jsonify({'error': 'This account has been deactivated. Contact admin.', 'code': 'USER_DEACTIVATED'}), 403

    token = generate_token(user)
    return jsonify({
        'message': 'Login successful',
        'token': token,
        'user': user.to_dict()
    }), 200

@auth_bp.route('/me', methods=['GET'])
@token_required
def get_current_user(current_user):
    return jsonify({'user': current_user.to_dict()}), 200

@auth_bp.route('/grant-access', methods=['POST'])
@token_required
@role_required('Patient')
def grant_doctor_access(current_user):
    data = request.get_json() or {}
    doctor_id = (data.get('doctorId') or data.get('doctor_id') or '').strip()

    if not doctor_id:
        return jsonify({'error': 'Doctor ID is required', 'code': 'VALIDATION_ERROR'}), 400

    if doctor_id == current_user.id:
        return jsonify({'error': 'Cannot grant access to self', 'code': 'INVALID_DOCTOR'}), 400

    doctor = User.query.filter_by(id=doctor_id, role='Doctor', is_active=True).first()
    if not doctor:
        return jsonify({'error': 'Doctor not found or inactive', 'code': 'DOCTOR_NOT_FOUND'}), 404

    existing = DoctorPatientAccess.query.filter_by(patient_id=current_user.id, doctor_id=doctor_id).first()
    if existing:
        return jsonify({'message': 'Access already granted to this doctor', 'access': existing.to_dict()}), 200

    access = DoctorPatientAccess(
        patient_id=current_user.id,
        doctor_id=doctor_id,
        granted_at=utc_now()
    )
    db.session.add(access)
    db.session.commit()

    return jsonify({'message': 'Doctor access granted successfully', 'access': access.to_dict()}), 201

@auth_bp.route('/revoke-access', methods=['POST'])
@token_required
@role_required('Patient')
def revoke_doctor_access(current_user):
    data = request.get_json() or {}
    doctor_id = (data.get('doctorId') or data.get('doctor_id') or '').strip()

    if not doctor_id:
        return jsonify({'error': 'Doctor ID is required', 'code': 'VALIDATION_ERROR'}), 400

    access = DoctorPatientAccess.query.filter_by(patient_id=current_user.id, doctor_id=doctor_id).first()
    if not access:
        return jsonify({'message': 'No existing access found to revoke'}), 200

    db.session.delete(access)
    db.session.commit()
    return jsonify({'message': 'Doctor access revoked successfully'}), 200

@auth_bp.route('/authorized-doctors', methods=['GET'])
@token_required
@role_required('Patient')
def get_authorized_doctors(current_user):
    grants = DoctorPatientAccess.query.filter_by(patient_id=current_user.id).all()
    doctor_ids = [g.doctor_id for g in grants]
    doctors = User.query.filter(User.id.in_(doctor_ids)).all() if doctor_ids else []
    return jsonify({
        'doctorIds': doctor_ids,
        'doctors': [d.to_dict() for d in doctors]
    }), 200

@auth_bp.route('/shared-patients', methods=['GET'])
@token_required
@role_required('Doctor')
def get_shared_patients(current_user):
    grants = DoctorPatientAccess.query.filter_by(doctor_id=current_user.id).all()
    patient_ids = [g.patient_id for g in grants]
    patients = User.query.filter(User.id.in_(patient_ids)).all() if patient_ids else []
    return jsonify({
        'patients': [p.to_dict() for p in patients]
    }), 200
