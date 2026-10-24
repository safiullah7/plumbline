#!/usr/bin/env bash
source "$(dirname "$0")/../_fixture/modules.sh"
# A patients module that exists in the code but has no docs folder yet.
mkdir -p apps/api/patients apps/web/patients
cat > apps/api/patients/store.js <<'JS'
// In-memory patient store for the demo app.
let patients = [];
module.exports = {
  list: ({ clinicId }) => patients.filter((p) => p.clinicId === clinicId),
  create: (p) => { const patient = { id: String(patients.length + 1), ...p }; patients.push(patient); return patient; },
};
JS
cat > apps/api/patients/routes.js <<'JS'
// Patients API: list a clinic's patients, with name and phone.
const store = require('./store');

function listPatients(req, res) {
  res.json(store.list({ clinicId: req.user.clinicId }));
}

module.exports = { listPatients };
JS
cat > apps/web/patients/PatientsPage.jsx <<'JS'
// Patients page: a plain list of the clinic's patients.
export function PatientsPage({ patients }) {
  return (
    <ul>
      {patients.map((p) => (
        <li key={p.id}>{p.name} {p.phone}</li>
      ))}
    </ul>
  );
}
JS
git add -A
git commit -qm "Patients code, no docs yet"
