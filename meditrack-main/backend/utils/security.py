import os
import uuid
from werkzeug.utils import secure_filename

ALLOWED_EXTENSIONS = {'pdf', 'jpg', 'jpeg', 'png'}

FILE_SIGNATURES = {
    'pdf': [b'%PDF-'],
    'jpg': [b'\xff\xd8\xff'],
    'jpeg': [b'\xff\xd8\xff'],
    'png': [b'\x89PNG\r\n\x1a\n'],
}

def get_file_extension(filename: str) -> str:
    """Extract lowercase file extension without dot."""
    if not filename or '.' not in filename:
        return ''
    return filename.rsplit('.', 1)[1].lower().strip()

def allowed_file(filename: str) -> bool:
    """Validate file extension against whitelist."""
    ext = get_file_extension(filename)
    return ext in ALLOWED_EXTENSIONS

def validate_file_signature(header_bytes: bytes, extension: str) -> bool:
    """
    Validate that the leading bytes match the expected file signature / magic numbers.
    Prevents file extension spoofing attacks (e.g. executable or script renamed to .pdf).
    """
    ext = extension.lower().strip()
    if ext not in FILE_SIGNATURES:
        return False
    
    signatures = FILE_SIGNATURES[ext]
    return any(header_bytes.startswith(sig) for sig in signatures)

def secure_random_filename(original_filename: str) -> str:
    """
    Generate an unpredictable randomized filename preserving the validated extension.
    Prevents filename collisions, directory traversal, and enumeration attacks.
    """
    ext = get_file_extension(original_filename)
    random_id = uuid.uuid4().hex
    return f"{random_id}.{ext}"

def is_safe_path(base_dir: str, target_path: str) -> bool:
    """
    Ensure target_path resides strictly within base_dir.
    Guards against path traversal (e.g. '../', '..\\').
    """
    abs_base = os.path.abspath(base_dir)
    abs_target = os.path.abspath(target_path)
    try:
        common = os.path.commonpath([abs_base, abs_target])
        return common == abs_base
    except ValueError:
        return False

def get_patient_storage_dir(base_upload_dir: str, patient_id: str) -> str:
    """
    Safely get and create patient-isolated storage folder.
    """
    safe_patient_folder = secure_filename(patient_id)
    if not safe_patient_folder:
        safe_patient_folder = "patient_unknown"
    folder_path = os.path.join(base_upload_dir, safe_patient_folder)
    os.makedirs(folder_path, exist_ok=True)
    return folder_path
