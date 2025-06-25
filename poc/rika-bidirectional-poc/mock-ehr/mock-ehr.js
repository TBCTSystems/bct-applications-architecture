// Mock EHR Server - Enhanced for OpenAPI Compliance
const express = require('express');
const cors = require('cors');
const app = express();
const PORT = 3001;

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true })); // For form data
app.use(cors());

// Serve static files (for CSS, JS, etc.)
app.use('/static', express.static('public'));

// This is our in-memory database with enhanced data
let donors = [
  {
    "id": 1,
    "category": { "id": 10, "name": "Individual" },
    "name": "John Wayne",
    "photoUrls": ["https://example.com/photos/john_wayne.jpg"],
    "tags": [{ "id": 1, "name": "VIP" }, { "id": 3, "name": "Regular" }],
    "status": "donated",
    "FIRS": "John",
    "LAST": "Wayne",
    "DOB": "19970423",
    "HCT": "40",
    "WGHT": "140.7",
    "HGHT": "69.7",
    "BG": "M"
  },
  {
    "id": 2,
    "category": { "id": 10, "name": "Individual" },
    "name": "Audrey Hepburn",
    "photoUrls": ["https://example.com/photos/audrey_hepburn.jpg"],
    "tags": [{ "id": 2, "name": "Recurring" }],
    "status": "checked-in",
    "FIRS": "Audrey",
    "LAST": "Hepburn",
    "DOB": "19970423",
    "HCT": "40",
    "WGHT": "140.7",
    "HGHT": "69.7",
    "BG": "F"
  },
  {
    "id": 3,
    "category": { "id": 20, "name": "Corporate" },
    "name": "MegaCorp Inc.",
    "photoUrls": [],
    "tags": [{ "id": 4, "name": "Corporate" }],
    "status": "not-available",
    "FIRS": "MegaCorp",
    "LAST": "Inc.",
    "DOB": "19970423",
    "HCT": "40",
    "WGHT": "140.7",
    "HGHT": "69.7",
    "BG": "U"
  },
  {
    "id": 4,
    "category": { "id": 10, "name": "Individual" },
    "name": "Grace Kelly",
    "photoUrls": [],
    "tags": [{ "id": 1, "name": "VIP" }, { "id": 5, "name": "First-time" }],
    "status": "donating",
    "FIRS": "Grace",
    "LAST": "Kelly",
    "DOB": "19970423",
    "HCT": "40",
    "WGHT": "140.7",
    "HGHT": "69.7",
    "BG": "F"
  },
  {
    "id": 5,
    "category": { "id": 10, "name": "Individual" },
    "name": "Clark Gable",
    "photoUrls": ["https://example.com/photos/clark_gable.jpg"],
    "tags": [{ "id": 2, "name": "Recurring" }],
    "status": "checked-in",
    "FIRS": "Clark",
    "LAST": "Gable",
    "DOB": "19970423",
    "HCT": "40",
    "WGHT": "140.7",
    "HGHT": "69.7",
    "BG": "M"
  }
];

let nextId = 6;

// In-memory storage for End of Run (EOR) data
let eorData = [];
let nextEorId = 1;


// Helper function to find donor by ID
const findDonorById = (id) => donors.find(d => d.id === parseInt(id));

// Helper function to validate donor data
const validateDonor = (donor) => {
  const errors = [];
  if (!donor.name) errors.push('Name is required');
  if (!donor.category) errors.push('Category is required');
  if (!donor.status) errors.push('Status is required');
  
  const validStatuses = ['not-available', 'checked-in', 'donating', 'donated'];
  if (donor.status && !validStatuses.includes(donor.status)) {
    errors.push('Invalid status. Must be one of: ' + validStatuses.join(', '));
  }
  
  return errors;
};

// GET /donors - Get all donors
app.get('/donors', (req, res) => {
  console.log(`[Mock EHR] Request received for all donors. Count: ${donors.length}`);
  res.json(donors);
});

// GET /donors/:id - Get a single donor by ID
app.get('/donors/:id', (req, res) => {
  const donorId = parseInt(req.params.id, 10);
  const verbose = req.query.verbose === 'true';
  
  console.log(`[Mock EHR] Request received for donor ID: ${donorId}, verbose: ${verbose}`);
  
  const donor = findDonorById(donorId);
  
  if (donor) {
    if (verbose) {
      // Return enhanced donor information when verbose is true
      const enhancedDonor = {
        ...donor,
        lastDonation: "2024-01-15T10:30:00Z",
        totalDonations: Math.floor(Math.random() * 20) + 1,
        bloodType: ["A+", "B+", "AB+", "O+", "A-", "B-", "AB-", "O-"][Math.floor(Math.random() * 8)],
        eligibilityStatus: "eligible"
      };
      res.json(enhancedDonor);
    } else {
      res.json(donor);
    }
  } else {
    res.status(404).json({ error: 'Donor not found', code: 404 });
  }
});

// POST /donors - Add a new donor
app.post('/donors', (req, res) => {
  console.log(`[Mock EHR] Request to add new donor:`, req.body);
  
  const errors = validateDonor(req.body);
  if (errors.length > 0) {
    return res.status(400).json({ error: 'Validation failed', details: errors });
  }
  
  const newDonor = {
    id: nextId++,
    category: req.body.category || { id: 10, name: "Individual" },
    name: req.body.name,
    photoUrls: req.body.photoUrls || [],
    tags: req.body.tags || [],
    status: req.body.status,
    FIRS: req.body.FIRS || req.body.name.split(' ')[0] || '',
    LAST: req.body.LAST || req.body.name.split(' ').slice(1).join(' ') || '',
    DOB: req.body.DOB || '',
    HCT: req.body.HCT || '',
    WGHT: req.body.WGHT || '',
    HGHT: req.body.HGHT || '',
    BG: req.body.BG || ''
  };
  
  donors.push(newDonor);
  console.log(`[Mock EHR] New donor added with ID: ${newDonor.id}`);
  
  res.status(201).json(newDonor);
});

// PUT /donors/:id - Update an existing donor
app.put('/donors/:id', (req, res) => {
  const donorId = parseInt(req.params.id, 10);
  console.log(`[Mock EHR] Request to update donor ID: ${donorId}`, req.body);
  
  const donorIndex = donors.findIndex(d => d.id === donorId);
  
  if (donorIndex === -1) {
    return res.status(404).json({ error: 'Donor not found', code: 404 });
  }
  
  const errors = validateDonor(req.body);
  if (errors.length > 0) {
    return res.status(400).json({ error: 'Validation failed', details: errors });
  }
  
  // Update the donor
  donors[donorIndex] = {
    ...donors[donorIndex],
    ...req.body,
    id: donorId // Ensure ID doesn't change
  };
  
  console.log(`[Mock EHR] Donor ID ${donorId} updated successfully`);
  res.status(204).send();
});

// DELETE /donors/:id - Delete a donor
app.delete('/donors/:id', (req, res) => {
  const donorId = parseInt(req.params.id, 10);
  console.log(`[Mock EHR] Request to delete donor ID: ${donorId}`);
  
  const donorIndex = donors.findIndex(d => d.id === donorId);
  
  if (donorIndex === -1) {
    return res.status(404).json({ error: 'Donor not found', code: 404 });
  }
  
  const deletedDonor = donors.splice(donorIndex, 1)[0];
  console.log(`[Mock EHR] Donor deleted:`, deletedDonor.name);
  
  res.status(204).send();
});

// POST /donors/select - Select a donor for processing
app.post('/donors/select', (req, res) => {
  const { donorId } = req.body;
  console.log(`[Mock EHR] Request to select donor ID: ${donorId}`);
  
  const donor = findDonorById(donorId);
  
  if (!donor) {
    return res.status(404).json({ error: 'Donor not found', code: 404 });
  }
  
  // Update donor status to 'donating' when selected
  const donorIndex = donors.findIndex(d => d.id === parseInt(donorId));
  donors[donorIndex].status = 'donating';
  
  console.log(`[Mock EHR] Donor ${donor.name} (ID: ${donorId}) selected and status updated to 'donating'`);
  
  res.json({
    status: 'success',
    message: `Donor ${donor.name} selected successfully`,
    donor: donors[donorIndex],
    selectedAt: new Date().toISOString()
  });
});

// POST /eor - Receive End of Run data
app.post('/eor', (req, res) => {
  console.log(`[Mock EHR] Received EOR data:`, req.body);
  
  // Accept any valid JSON object as EOR data
  if (!req.body || typeof req.body !== 'object') {
    return res.status(400).json({ 
      error: 'Invalid EOR data', 
      message: 'EOR data must be a valid JSON object' 
    });
  }
  
  const eorEntry = {
    id: nextEorId++,
    data: req.body,
    receivedAt: new Date().toISOString(),
    source: req.headers['user-agent'] || 'unknown'
  };
  
  eorData.push(eorEntry);
  console.log(`[Mock EHR] EOR data stored with ID: ${eorEntry.id}`);
  
  res.status(201).json({
    status: 'success',
    message: 'EOR data received and stored successfully',
    eorId: eorEntry.id,
    receivedAt: eorEntry.receivedAt
  });
});

// GET /eor - Get all EOR data
app.get('/eor', (req, res) => {
  console.log(`[Mock EHR] Request received for all EOR data. Count: ${eorData.length}`);
  
  const limit = parseInt(req.query.limit) || 50;
  const offset = parseInt(req.query.offset) || 0;
  
  const paginatedData = eorData.slice(offset, offset + limit);
  
  res.json({
    total: eorData.length,
    limit: limit,
    offset: offset,
    data: paginatedData
  });
});

// GET /eor/:id - Get specific EOR data by ID
app.get('/eor/:id', (req, res) => {
  const eorId = parseInt(req.params.id, 10);
  console.log(`[Mock EHR] Request received for EOR ID: ${eorId}`);
  
  const eorEntry = eorData.find(e => e.id === eorId);
  
  if (eorEntry) {
    res.json(eorEntry);
  } else {
    res.status(404).json({ error: 'EOR data not found', code: 404 });
  }
});

// DELETE /eor - Clear all EOR data (useful for testing)
app.delete('/eor', (req, res) => {
  console.log(`[Mock EHR] Request to clear all EOR data`);
  const deletedCount = eorData.length;
  eorData = [];
  nextEorId = 1;
  
  console.log(`[Mock EHR] Cleared ${deletedCount} EOR entries`);
  res.json({
    status: 'success',
    message: `Cleared ${deletedCount} EOR entries`,
    deletedCount: deletedCount
  });
});

// DELETE /eor/:id - Delete specific EOR data by ID
app.delete('/eor/:id', (req, res) => {
  const eorId = parseInt(req.params.id, 10);
  console.log(`[Mock EHR] Request to delete EOR ID: ${eorId}`);
  
  const eorIndex = eorData.findIndex(e => e.id === eorId);
  
  if (eorIndex === -1) {
    return res.status(404).json({ error: 'EOR data not found', code: 404 });
  }
  
  const deletedEor = eorData.splice(eorIndex, 1)[0];
  console.log(`[Mock EHR] EOR data deleted:`, deletedEor.id);
  
  res.status(204).send();
});

// Web Interface Routes

// Main dashboard
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Mock EHR Dashboard</title>
        <link rel="stylesheet" href="/static/style.css">
    </head>
    <body>
        <div class="container">
            <header>
                <h1>🏥 Mock EHR Dashboard</h1>
                <p>Donor Management & EOR Data Interface</p>
            </header>
            
            <nav class="nav-cards">
                <a href="/donors-interface" class="nav-card">
                    <h3>👥 Manage Donors</h3>
                    <p>Add new donors and view existing ones</p>
                </a>
                <a href="/eor-interface" class="nav-card">
                    <h3>📊 EOR Data</h3>
                    <p>Browse End of Run data</p>
                </a>
                <a href="/api-docs" class="nav-card">
                    <h3>📋 API Documentation</h3>
                    <p>View available REST endpoints</p>
                </a>
            </nav>
            
            <div class="stats">
                <div class="stat-card">
                    <h4>Total Donors</h4>
                    <span class="stat-number">${donors.length}</span>
                </div>
                <div class="stat-card">
                    <h4>EOR Records</h4>
                    <span class="stat-number">${eorData.length}</span>
                </div>
            </div>
        </div>
    </body>
    </html>
  `);
});

// Donors management interface
app.get('/donors-interface', (req, res) => {
  const donorsHtml = donors.map(donor => `
    <tr>
      <td>${donor.id}</td>
      <td>${donor.name}</td>
      <td><span class="status-badge status-${donor.status}">${donor.status}</span></td>
      <td>${donor.category.name}</td>
      <td>${donor.BG || 'N/A'}</td>
      <td>${donor.HCT || 'N/A'}</td>
      <td>${donor.WGHT || 'N/A'}</td>
      <td>${donor.HGHT || 'N/A'}</td>
      <td>
        <button onclick="deleteDonor(${donor.id})" class="btn btn-danger btn-sm">Delete</button>
      </td>
    </tr>
  `).join('');

  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Donor Management - Mock EHR</title>
        <link rel="stylesheet" href="/static/style.css">
    </head>
    <body>
        <div class="container">
            <header>
                <h1>👥 Donor Management</h1>
                <a href="/" class="btn btn-secondary">← Back to Dashboard</a>
            </header>
            
            <div class="content-grid">
                <div class="form-section">
                    <h2>Add New Donor</h2>
                    <form id="donorForm" onsubmit="addDonor(event)">
                        <div class="form-group">
                            <label for="name">Full Name *</label>
                            <input type="text" id="name" name="name" required>
                        </div>
                        
                        <div class="form-group">
                            <label for="firstName">First Name</label>
                            <input type="text" id="firstName" name="firstName">
                        </div>
                        
                        <div class="form-group">
                            <label for="lastName">Last Name</label>
                            <input type="text" id="lastName" name="lastName">
                        </div>
                        
                        <div class="form-group">
                            <label for="dob">Date of Birth</label>
                            <input type="date" id="dob" name="dob">
                        </div>
                        
                        <div class="form-group">
                            <label for="bloodGroup">Blood Group</label>
                            <select id="bloodGroup" name="bloodGroup">
                                <option value="">Select...</option>
                                <option value="A+">A+</option>
                                <option value="A-">A-</option>
                                <option value="B+">B+</option>
                                <option value="B-">B-</option>
                                <option value="AB+">AB+</option>
                                <option value="AB-">AB-</option>
                                <option value="O+">O+</option>
                                <option value="O-">O-</option>
                            </select>
                        </div>
                        
                        <div class="form-group">
                            <label for="hematocrit">Hematocrit (%)</label>
                            <input type="number" id="hematocrit" name="hematocrit" min="0" max="100" step="0.1" placeholder="e.g., 40.5">
                        </div>
                        
                        <div class="form-group">
                            <label for="weight">Weight (lbs)</label>
                            <input type="number" id="weight" name="weight" min="0" step="0.1" placeholder="e.g., 150.5">
                        </div>
                        
                        <div class="form-group">
                            <label for="height">Height (inches)</label>
                            <input type="number" id="height" name="height" min="0" step="0.1" placeholder="e.g., 69.5">
                        </div>
                        
                        <div class="form-group">
                            <label for="status">Status *</label>
                            <select id="status" name="status" required>
                                <option value="not-available">Not Available</option>
                                <option value="checked-in">Checked In</option>
                                <option value="donating">Donating</option>
                                <option value="donated">Donated</option>
                            </select>
                        </div>
                        
                        <div class="form-group">
                            <label for="category">Category</label>
                            <select id="category" name="category">
                                <option value="Individual">Individual</option>
                                <option value="Corporate">Corporate</option>
                            </select>
                        </div>
                        
                        <button type="submit" class="btn btn-primary">Add Donor</button>
                    </form>
                </div>
                
                <div class="table-section">
                    <h2>Current Donors (${donors.length})</h2>
                    <div class="table-container">
                        <table class="donors-table">
                            <thead>
                                <tr>
                                    <th>ID</th>
                                    <th>Name</th>
                                    <th>Status</th>
                                    <th>Category</th>
                                    <th>Blood Group</th>
                                    <th>HCT (%)</th>
                                    <th>Weight (lbs)</th>
                                    <th>Height (in)</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${donorsHtml}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
        
        <script>
            async function addDonor(event) {
                event.preventDefault();
                const formData = new FormData(event.target);
                
                const donorData = {
                    name: formData.get('name'),
                    status: formData.get('status'),
                    category: {
                        id: formData.get('category') === 'Corporate' ? 20 : 10,
                        name: formData.get('category')
                    },
                    FIRS: formData.get('firstName') || formData.get('name').split(' ')[0],
                    LAST: formData.get('lastName') || formData.get('name').split(' ').slice(1).join(' '),
                    DOB: formData.get('dob') ? formData.get('dob').replace(/-/g, '') : '',
                    BG: formData.get('bloodGroup') || '',
                    HCT: formData.get('hematocrit') || '',
                    WGHT: formData.get('weight') || '',
                    HGHT: formData.get('height') || '',
                    tags: []
                };
                
                try {
                    const response = await fetch('/donors', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                        },
                        body: JSON.stringify(donorData)
                    });
                    
                    if (response.ok) {
                        alert('Donor added successfully!');
                        window.location.reload();
                    } else {
                        const error = await response.json();
                        alert('Error adding donor: ' + (error.details ? error.details.join(', ') : error.error));
                    }
                } catch (error) {
                    alert('Error adding donor: ' + error.message);
                }
            }
            
            async function deleteDonor(id) {
                if (confirm('Are you sure you want to delete this donor?')) {
                    try {
                        const response = await fetch('/donors/' + id, {
                            method: 'DELETE'
                        });
                        
                        if (response.ok) {
                            alert('Donor deleted successfully!');
                            window.location.reload();
                        } else {
                            alert('Error deleting donor');
                        }
                    } catch (error) {
                        alert('Error deleting donor: ' + error.message);
                    }
                }
            }
        </script>
    </body>
    </html>
  `);
});

// EOR data interface
app.get('/eor-interface', (req, res) => {
  const eorHtml = eorData.map(eor => `
    <tr>
      <td>${eor.id}</td>
      <td>${new Date(eor.receivedAt).toLocaleString()}</td>
      <td>${eor.source}</td>
      <td>
        <button onclick="viewEorData(${eor.id})" class="btn btn-info btn-sm">View</button>
        <button onclick="deleteEor(${eor.id})" class="btn btn-danger btn-sm">Delete</button>
      </td>
    </tr>
  `).join('');

  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>EOR Data Browser - Mock EHR</title>
        <link rel="stylesheet" href="/static/style.css">
    </head>
    <body>
        <div class="container">
            <header>
                <h1>📊 EOR Data Browser</h1>
                <a href="/" class="btn btn-secondary">← Back to Dashboard</a>
            </header>
            
            <div class="eor-controls">
                <button onclick="clearAllEor()" class="btn btn-warning">Clear All EOR Data</button>
                <button onclick="refreshEor()" class="btn btn-info">Refresh</button>
            </div>
            
            <div class="table-section">
                <h2>EOR Records (${eorData.length})</h2>
                <div class="table-container">
                    <table class="eor-table">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Received At</th>
                                <th>Source</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${eorHtml}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
        
        <!-- Modal for viewing EOR data -->
        <div id="eorModal" class="modal">
            <div class="modal-content">
                <span class="close" onclick="closeModal()">&times;</span>
                <h2>EOR Data Details</h2>
                <pre id="eorDataContent"></pre>
            </div>
        </div>
        
        <script>
            async function viewEorData(id) {
                try {
                    const response = await fetch('/eor/' + id);
                    if (response.ok) {
                        const eorData = await response.json();
                        document.getElementById('eorDataContent').textContent = JSON.stringify(eorData, null, 2);
                        document.getElementById('eorModal').style.display = 'block';
                    } else {
                        alert('Error fetching EOR data');
                    }
                } catch (error) {
                    alert('Error fetching EOR data: ' + error.message);
                }
            }
            
            function closeModal() {
                document.getElementById('eorModal').style.display = 'none';
            }
            
            async function deleteEor(id) {
                if (confirm('Are you sure you want to delete this EOR record?')) {
                    try {
                        const response = await fetch('/eor/' + id, {
                            method: 'DELETE'
                        });
                        
                        if (response.ok) {
                            alert('EOR record deleted successfully!');
                            window.location.reload();
                        } else {
                            alert('Error deleting EOR record');
                        }
                    } catch (error) {
                        alert('Error deleting EOR record: ' + error.message);
                    }
                }
            }
            
            async function clearAllEor() {
                if (confirm('Are you sure you want to clear ALL EOR data? This cannot be undone.')) {
                    try {
                        const response = await fetch('/eor', {
                            method: 'DELETE'
                        });
                        
                        if (response.ok) {
                            alert('All EOR data cleared successfully!');
                            window.location.reload();
                        } else {
                            alert('Error clearing EOR data');
                        }
                    } catch (error) {
                        alert('Error clearing EOR data: ' + error.message);
                    }
                }
            }
            
            function refreshEor() {
                window.location.reload();
            }
            
            // Close modal when clicking outside of it
            window.onclick = function(event) {
                const modal = document.getElementById('eorModal');
                if (event.target == modal) {
                    modal.style.display = 'none';
                }
            }
        </script>
    </body>
    </html>
  `);
});

// API documentation page
app.get('/api-docs', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>API Documentation - Mock EHR</title>
        <link rel="stylesheet" href="/static/style.css">
    </head>
    <body>
        <div class="container">
            <header>
                <h1>📋 API Documentation</h1>
                <a href="/" class="btn btn-secondary">← Back to Dashboard</a>
            </header>
            
            <div class="api-docs">
                <h2>Available Endpoints</h2>
                
                <div class="endpoint-group">
                    <h3>Donor Management</h3>
                    <div class="endpoint">
                        <span class="method get">GET</span>
                        <code>/donors</code>
                        <p>Get all donors</p>
                    </div>
                    <div class="endpoint">
                        <span class="method get">GET</span>
                        <code>/donors/:id</code>
                        <p>Get donor by ID (add ?verbose=true for enhanced data)</p>
                    </div>
                    <div class="endpoint">
                        <span class="method post">POST</span>
                        <code>/donors</code>
                        <p>Add new donor</p>
                    </div>
                    <div class="endpoint">
                        <span class="method put">PUT</span>
                        <code>/donors/:id</code>
                        <p>Update existing donor</p>
                    </div>
                    <div class="endpoint">
                        <span class="method delete">DELETE</span>
                        <code>/donors/:id</code>
                        <p>Delete donor</p>
                    </div>
                    <div class="endpoint">
                        <span class="method post">POST</span>
                        <code>/donors/select</code>
                        <p>Select donor for processing</p>
                    </div>
                </div>
                
                <div class="endpoint-group">
                    <h3>EOR Data Management</h3>
                    <div class="endpoint">
                        <span class="method get">GET</span>
                        <code>/eor</code>
                        <p>Get all EOR data (supports limit and offset parameters)</p>
                    </div>
                    <div class="endpoint">
                        <span class="method get">GET</span>
                        <code>/eor/:id</code>
                        <p>Get specific EOR data by ID</p>
                    </div>
                    <div class="endpoint">
                        <span class="method post">POST</span>
                        <code>/eor</code>
                        <p>Submit new EOR data</p>
                    </div>
                    <div class="endpoint">
                        <span class="method delete">DELETE</span>
                        <code>/eor</code>
                        <p>Clear all EOR data</p>
                    </div>
                    <div class="endpoint">
                        <span class="method delete">DELETE</span>
                        <code>/eor/:id</code>
                        <p>Delete specific EOR data</p>
                    </div>
                </div>
                
                <div class="endpoint-group">
                    <h3>System</h3>
                    <div class="endpoint">
                        <span class="method get">GET</span>
                        <code>/health</code>
                        <p>Health check endpoint</p>
                    </div>
                </div>
            </div>
        </div>
    </body>
    </html>
  `);
});


// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    donors_count: donors.length
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('[Mock EHR] Error:', err);
  res.status(500).json({ error: 'Internal server error', message: err.message });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found', path: req.path });
});

app.listen(PORT, () => {
  console.log(`[Mock EHR] Server is running on http://localhost:${PORT}`);
  console.log(`[Mock EHR] Web Interface:`);
  console.log(`  GET    / - Main Dashboard`);
  console.log(`  GET    /donors-interface - Donor Management Interface`);
  console.log(`  GET    /eor-interface - EOR Data Browser`);
  console.log(`  GET    /api-docs - API Documentation`);
  console.log(`[Mock EHR] REST API endpoints:`);
  console.log(`  GET    /donors - Get all donors`);
  console.log(`  GET    /donors/:id - Get donor by ID`);
  console.log(`  POST   /donors - Add new donor`);
  console.log(`  PUT    /donors/:id - Update donor`);
  console.log(`  DELETE /donors/:id - Delete donor`);
  console.log(`  POST   /donors/select - Select donor for processing`);
  console.log(`  POST   /eor - Receive End of Run data`);
  console.log(`  GET    /eor - Get all EOR data`);
  console.log(`  GET    /eor/:id - Get specific EOR data`);
  console.log(`  DELETE /eor - Clear all EOR data`);
  console.log(`  DELETE /eor/:id - Delete specific EOR data`);
  console.log(`  GET    /health - Health check`);
  console.log(`[Mock EHR] Initial donors loaded: ${donors.length}`);
});