// Mock EHR Server - Enhanced for OpenAPI Compliance
const express = require('express');
const cors = require('cors');
const app = express();
const PORT = 3001;

// Middleware
app.use(express.json());
app.use(cors());

// This is our in-memory database with enhanced data
let donors = [
  {
    "id": 1,
    "category": { "id": 10, "name": "Individual" },
    "name": "John Wayne",
    "photoUrls": ["https://example.com/photos/john_wayne.jpg"],
    "tags": [{ "id": 1, "name": "VIP" }, { "id": 3, "name": "Regular" }],
    "status": "donated"
  },
  {
    "id": 2,
    "category": { "id": 10, "name": "Individual" },
    "name": "Audrey Hepburn",
    "photoUrls": ["https://example.com/photos/audrey_hepburn.jpg"],
    "tags": [{ "id": 2, "name": "Recurring" }],
    "status": "checked-in"
  },
  {
    "id": 3,
    "category": { "id": 20, "name": "Corporate" },
    "name": "MegaCorp Inc.",
    "photoUrls": [],
    "tags": [{ "id": 4, "name": "Corporate" }],
    "status": "not-available"
  },
  {
    "id": 4,
    "category": { "id": 10, "name": "Individual" },
    "name": "Grace Kelly",
    "photoUrls": [],
    "tags": [{ "id": 1, "name": "VIP" }, { "id": 5, "name": "First-time" }],
    "status": "donating"
  },
  {
    "id": 5,
    "category": { "id": 10, "name": "Individual" },
    "name": "Clark Gable",
    "photoUrls": ["https://example.com/photos/clark_gable.jpg"],
    "tags": [{ "id": 2, "name": "Recurring" }],
    "status": "checked-in"
  }
];

let nextId = 6;

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
    status: req.body.status
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
  console.log(`[Mock EHR] Available endpoints:`);
  console.log(`  GET    /donors - Get all donors`);
  console.log(`  GET    /donors/:id - Get donor by ID`);
  console.log(`  POST   /donors - Add new donor`);
  console.log(`  PUT    /donors/:id - Update donor`);
  console.log(`  DELETE /donors/:id - Delete donor`);
  console.log(`  GET    /health - Health check`);
  console.log(`[Mock EHR] Initial donors loaded: ${donors.length}`);
});