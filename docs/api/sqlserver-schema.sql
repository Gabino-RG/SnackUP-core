-- SQL Server schema for a NEW, empty SnackUP_Local database.
-- Generated from the pinned API models by tools/sqlserver_demo.py.
USE [master];
GO
IF DB_ID(N'SnackUP_Local') IS NULL CREATE DATABASE [SnackUP_Local];
GO
USE [SnackUP_Local];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE outbox_events (
	id INTEGER NOT NULL IDENTITY,
	event_id NVARCHAR(32) NOT NULL,
	topic NVARCHAR(128) NOT NULL,
	event_type NVARCHAR(80) NOT NULL,
	data NVARCHAR(max) NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	published_at DATETIMEOFFSET NULL,
	publish_attempts INTEGER NOT NULL,
	last_error NVARCHAR(80) NULL,
	next_attempt_at DATETIMEOFFSET NULL,
	PRIMARY KEY (id),
	UNIQUE (event_id)
);
GO

CREATE INDEX ix_outbox_events_topic ON outbox_events (topic);
GO

CREATE INDEX ix_outbox_events_next_attempt_at ON outbox_events (next_attempt_at);
GO

CREATE INDEX ix_outbox_events_published_at ON outbox_events (published_at);
GO

CREATE TABLE careers (
	id NVARCHAR(128) NOT NULL,
	name NVARCHAR(160) NOT NULL,
	is_active BIT NOT NULL,
	PRIMARY KEY (id)
);
GO

CREATE TABLE businesses (
	id NVARCHAR(128) NOT NULL,
	name NVARCHAR(160) NOT NULL,
	category NVARCHAR(80) NOT NULL,
	description NVARCHAR(2000) NOT NULL,
	image_url NVARCHAR(2048) NULL,
	timezone NVARCHAR(80) NOT NULL,
	cafeteria_id NVARCHAR(120) NOT NULL,
	cafeteria_name NVARCHAR(160) NOT NULL,
	is_active BIT NOT NULL,
	is_open BIT NOT NULL,
	version INTEGER NOT NULL,
	next_order_number INTEGER NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CHECK (version >= 1),
	CHECK (next_order_number >= 1)
);
GO

CREATE INDEX ix_businesses_is_active ON businesses (is_active);
GO

CREATE TABLE users (
	id NVARCHAR(128) NOT NULL,
	email NVARCHAR(254) NOT NULL,
	display_name NVARCHAR(160) NOT NULL,
	password_hash NVARCHAR(256) NOT NULL,
	role NVARCHAR(16) NOT NULL,
	business_id NVARCHAR(128) NULL,
	is_active BIT NOT NULL,
	is_master BIT NOT NULL,
	approval_status NVARCHAR(16) NOT NULL,
	email_verified BIT NOT NULL,
	version INTEGER NOT NULL,
	auth_version INTEGER NOT NULL,
	numero_de_control NVARCHAR(100) NULL,
	avatar_url NVARCHAR(1000) NULL,
	institutional_verified_at DATETIMEOFFSET NULL,
	last_login_at DATETIMEOFFSET NULL,
	created_at DATETIMEOFFSET NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT ck_user_role CHECK (role IN ('admin','business','user','pending')),
	CONSTRAINT ck_user_approval CHECK (approval_status IN ('approved','pending','rejected')),
	CONSTRAINT ck_master_role CHECK (is_master = 0 OR role = 'admin'),
	CONSTRAINT ck_user_business_role CHECK (role = 'business' OR business_id IS NULL),
	UNIQUE (email),
	FOREIGN KEY(business_id) REFERENCES businesses (id) ON DELETE NO ACTION
);
GO

CREATE UNIQUE INDEX uq_active_business_operator ON users (business_id) WHERE role = 'business' AND is_active = 1 AND approval_status = 'approved' AND business_id IS NOT NULL;
GO

CREATE UNIQUE INDEX uq_users_numero_de_control ON users (numero_de_control) WHERE [numero_de_control] IS NOT NULL;
GO

CREATE TABLE academic_groups (
	id NVARCHAR(128) NOT NULL,
	career_id NVARCHAR(128) NOT NULL,
	name NVARCHAR(160) NOT NULL,
	is_active BIT NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(career_id) REFERENCES careers (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_academic_groups_career_id ON academic_groups (career_id);
GO

CREATE TABLE products (
	id NVARCHAR(128) NOT NULL,
	business_id NVARCHAR(128) NOT NULL,
	name NVARCHAR(160) NOT NULL,
	description NVARCHAR(2000) NOT NULL,
	category NVARCHAR(120) NOT NULL,
	subcategory NVARCHAR(80) NULL,
	preparation_minutes INTEGER NULL,
	calories INTEGER NULL,
	price NUMERIC(12, 2) NOT NULL,
	stock INTEGER NULL,
	image_url NVARCHAR(2048) NULL,
	is_available BIT NOT NULL,
	manual_available BIT NOT NULL,
	is_featured BIT NOT NULL,
	is_deleted BIT NOT NULL,
	deleted_at DATETIMEOFFSET NULL,
	version INTEGER NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CHECK (version >= 1),
	CHECK (price >= 0.01 AND price <= 10000),
	CHECK (stock IS NULL OR stock >= 0),
	CHECK (stock IS NULL OR stock != 0 OR is_available = 0),
	CONSTRAINT ck_product_preparation_minutes CHECK (preparation_minutes IS NULL OR preparation_minutes >= 0),
	CONSTRAINT ck_product_calories CHECK (calories IS NULL OR calories >= 0),
	FOREIGN KEY(business_id) REFERENCES businesses (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_products_business_available ON products (business_id, is_available);
GO

CREATE INDEX ix_products_business_catalog ON products (business_id, is_deleted, category);
GO

CREATE TABLE academic_records (
	id NVARCHAR(128) NOT NULL,
	email NVARCHAR(254) NOT NULL,
	institutional_id NVARCHAR(100) NOT NULL,
	display_name NVARCHAR(160) NOT NULL,
	kind NVARCHAR(16) NOT NULL,
	career_id NVARCHAR(128) NULL,
	group_id NVARCHAR(128) NULL,
	is_active BIT NOT NULL,
	source NVARCHAR(200) NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_roster_identity UNIQUE (kind, institutional_id),
	CONSTRAINT ck_roster_kind CHECK (kind IN ('student','staff')),
	CONSTRAINT ck_student_career CHECK (kind != 'student' OR career_id IS NOT NULL),
	CONSTRAINT ck_roster_group_career CHECK (group_id IS NULL OR career_id IS NOT NULL),
	UNIQUE (email),
	FOREIGN KEY(career_id) REFERENCES careers (id) ON DELETE NO ACTION,
	FOREIGN KEY(group_id) REFERENCES academic_groups (id) ON DELETE NO ACTION
);
GO

CREATE TABLE access_requests (
	id NVARCHAR(128) NOT NULL,
	user_id NVARCHAR(128) NOT NULL,
	email NVARCHAR(254) NOT NULL,
	display_name NVARCHAR(160) NOT NULL,
	requested_role NVARCHAR(16) NOT NULL,
	request_context NVARCHAR(400) NOT NULL,
	provider NVARCHAR(16) NOT NULL,
	email_verified BIT NOT NULL,
	approval_status NVARCHAR(16) NOT NULL,
	version INTEGER NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	reviewed_by NVARCHAR(128) NULL,
	note NVARCHAR(500) NOT NULL,
	decided_at DATETIMEOFFSET NULL,
	PRIMARY KEY (id),
	CONSTRAINT ck_requested_role CHECK (requested_role IN ('admin','business')),
	CONSTRAINT ck_request_approval CHECK (approval_status IN ('pending','approved','rejected')),
	UNIQUE (user_id),
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE NO ACTION,
	FOREIGN KEY(reviewed_by) REFERENCES users (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_access_requests_approval_status ON access_requests (approval_status);
GO

CREATE TABLE verification_tokens (
	id NVARCHAR(128) NOT NULL,
	user_id NVARCHAR(128) NOT NULL,
	email NVARCHAR(254) NOT NULL,
	purpose NVARCHAR(16) NOT NULL,
	token_hash NVARCHAR(64) NOT NULL,
	expires_at DATETIMEOFFSET NOT NULL,
	used_at DATETIMEOFFSET NULL,
	registration_data NVARCHAR(max) NULL,
	created_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT ck_verification_purpose CHECK (purpose IN ('verify','reset')),
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE NO ACTION,
	UNIQUE (token_hash)
);
GO

CREATE INDEX ix_verification_tokens_user_id ON verification_tokens (user_id);
GO

CREATE INDEX ix_verification_tokens_expiry ON verification_tokens (expires_at);
GO

CREATE TABLE account_audit_events (
	id NVARCHAR(128) NOT NULL,
	actor_id NVARCHAR(128) NULL,
	action NVARCHAR(80) NOT NULL,
	target_type NVARCHAR(32) NOT NULL,
	target_id NVARCHAR(128) NOT NULL,
	data NVARCHAR(max) NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(actor_id) REFERENCES users (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_account_audit_target ON account_audit_events (target_type, target_id);
GO

CREATE INDEX ix_account_audit_events_actor_id ON account_audit_events (actor_id);
GO

CREATE TABLE orders (
	id NVARCHAR(128) NOT NULL,
	business_id NVARCHAR(128) NOT NULL,
	student_id NVARCHAR(128) NOT NULL,
	order_number INTEGER NOT NULL,
	version INTEGER NOT NULL,
	status NVARCHAR(20) NOT NULL,
	customer_name NVARCHAR(160) NOT NULL,
	customer_institutional_id NVARCHAR(100) NULL,
	payment_method NVARCHAR(30) NOT NULL,
	payment_status NVARCHAR(30) NOT NULL,
	total NUMERIC(14, 2) NOT NULL,
	subtotal NUMERIC(14, 2) NULL,
	pickup_code NVARCHAR(32) NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	scheduled_pickup_time DATETIMEOFFSET NULL,
	accepted_at DATETIMEOFFSET NULL,
	preparing_at DATETIMEOFFSET NULL,
	ready_at DATETIMEOFFSET NULL,
	completed_at DATETIMEOFFSET NULL,
	cancelled_at DATETIMEOFFSET NULL,
	cancel_reason NVARCHAR(60) NULL,
	cancel_notes NVARCHAR(500) NULL,
	cancelled_by NVARCHAR(max) NULL,
	cancelled_by_role NVARCHAR(16) NULL,
	stock_restored BIT NOT NULL,
	verification_method NVARCHAR(10) NULL,
	verified_by NVARCHAR(max) NULL,
	verified_at DATETIMEOFFSET NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_business_order_number UNIQUE (business_id, order_number),
	CHECK (order_number >= 1 AND version >= 1 AND total >= 0),
	CHECK (status IN ('pending','accepted','preparing','ready','completed','cancelled')),
	FOREIGN KEY(business_id) REFERENCES businesses (id) ON DELETE NO ACTION,
	FOREIGN KEY(student_id) REFERENCES users (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_orders_student_status ON orders (student_id, status);
GO

CREATE INDEX ix_orders_student_created ON orders (student_id, created_at, id);
GO

CREATE INDEX ix_orders_business_updated ON orders (business_id, status, updated_at, id);
GO

CREATE INDEX ix_orders_business_cancelled ON orders (business_id, cancelled_at);
GO

CREATE UNIQUE INDEX uq_orders_v3_pickup_code ON orders (pickup_code) WHERE pickup_code IS NOT NULL;
GO

CREATE INDEX ix_orders_business_active ON orders (business_id, status, created_at, id);
GO

CREATE INDEX ix_orders_business_completed ON orders (business_id, completed_at);
GO

CREATE TABLE media_files (
	id NVARCHAR(128) NOT NULL,
	business_id NVARCHAR(128) NULL,
	owner_id NVARCHAR(128) NULL,
	purpose NVARCHAR(16) NOT NULL,
	filename NVARCHAR(80) NOT NULL,
	mime_type NVARCHAR(30) NOT NULL,
	size INTEGER NOT NULL,
	width INTEGER NULL,
	height INTEGER NULL,
	deleted_at DATETIMEOFFSET NULL,
	created_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(business_id) REFERENCES businesses (id) ON DELETE NO ACTION,
	FOREIGN KEY(owner_id) REFERENCES users (id) ON DELETE NO ACTION,
	UNIQUE (filename)
);
GO

CREATE INDEX ix_media_files_business_id ON media_files (business_id);
GO

CREATE INDEX ix_media_files_owner_id ON media_files (owner_id);
GO

CREATE TABLE devices (
	id NVARCHAR(128) NOT NULL,
	user_id NVARCHAR(128) NOT NULL,
	token NVARCHAR(max) NOT NULL,
	token_hash NVARCHAR(64) NOT NULL,
	platform NVARCHAR(16) NOT NULL,
	provider NVARCHAR(16) NOT NULL,
	session_family_id NVARCHAR(128) NOT NULL,
	last_active_at DATETIMEOFFSET NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT ck_device_platform CHECK (platform IN ('android','ios','web')),
	CONSTRAINT ck_device_provider CHECK (provider IN ('fcm','apns','webpush')),
	CONSTRAINT ck_device_platform_provider CHECK (provider = 'fcm' OR (provider = 'apns' AND platform = 'ios') OR (provider = 'webpush' AND platform = 'web')),
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE NO ACTION,
	UNIQUE (token_hash)
);
GO

CREATE INDEX ix_devices_user_id ON devices (user_id);
GO

CREATE INDEX ix_devices_session_family_id ON devices (session_family_id);
GO

CREATE TABLE refresh_sessions (
	id NVARCHAR(128) NOT NULL,
	user_id NVARCHAR(128) NOT NULL,
	family_id NVARCHAR(128) NOT NULL,
	token_hash NVARCHAR(64) NOT NULL,
	auth_version INTEGER NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	expires_at DATETIMEOFFSET NOT NULL,
	rotated_at DATETIMEOFFSET NULL,
	revoked_at DATETIMEOFFSET NULL,
	device_id NVARCHAR(128) NULL,
	replaced_by_id NVARCHAR(128) NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE NO ACTION,
	UNIQUE (token_hash),
	FOREIGN KEY(device_id) REFERENCES devices (id) ON DELETE NO ACTION,
	FOREIGN KEY(replaced_by_id) REFERENCES refresh_sessions (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_refresh_sessions_user_revoked ON refresh_sessions (user_id, revoked_at);
GO

CREATE INDEX ix_refresh_sessions_family_id ON refresh_sessions (family_id);
GO

CREATE INDEX ix_refresh_sessions_user_id ON refresh_sessions (user_id);
GO

CREATE INDEX ix_refresh_sessions_expiry ON refresh_sessions (expires_at);
GO

CREATE TABLE order_items (
	id NVARCHAR(128) NOT NULL,
	order_id NVARCHAR(128) NOT NULL,
	product_id NVARCHAR(128) NOT NULL,
	name NVARCHAR(160) NOT NULL,
	quantity INTEGER NOT NULL,
	price NUMERIC(12, 2) NOT NULL,
	notes NVARCHAR(500) NOT NULL,
	reserved_quantity INTEGER NOT NULL,
	PRIMARY KEY (id),
	CHECK (quantity > 0 AND price >= 0),
	CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity),
	FOREIGN KEY(order_id) REFERENCES orders (id) ON DELETE NO ACTION,
	FOREIGN KEY(product_id) REFERENCES products (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_order_items_order_id ON order_items (order_id);
GO

CREATE INDEX ix_order_items_product_id ON order_items (product_id);
GO

CREATE TABLE order_transitions (
	id NVARCHAR(128) NOT NULL,
	order_id NVARCHAR(128) NOT NULL,
	actor_id NVARCHAR(128) NOT NULL,
	from_status NVARCHAR(20) NULL,
	to_status NVARCHAR(20) NOT NULL,
	version INTEGER NOT NULL,
	action NVARCHAR(48) NULL,
	actor_role NVARCHAR(16) NULL,
	payload NVARCHAR(max) NULL,
	created_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_order_transition_version UNIQUE (order_id, version),
	FOREIGN KEY(order_id) REFERENCES orders (id) ON DELETE NO ACTION,
	FOREIGN KEY(actor_id) REFERENCES users (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_order_transitions_order_id ON order_transitions (order_id);
GO

CREATE TABLE idempotency_records (
	id NVARCHAR(128) NOT NULL,
	user_id NVARCHAR(128) NOT NULL,
	[key] NVARCHAR(128) NOT NULL,
	payload_hash NVARCHAR(64) NOT NULL,
	order_id NVARCHAR(128) NOT NULL,
	response_json NVARCHAR(max) NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	expires_at DATETIMEOFFSET NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_user_order_idempotency UNIQUE (user_id, [key]),
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE NO ACTION,
	FOREIGN KEY(order_id) REFERENCES orders (id) ON DELETE NO ACTION
);
GO

CREATE TABLE reviews (
	id NVARCHAR(128) NOT NULL,
	order_id NVARCHAR(128) NOT NULL,
	user_id NVARCHAR(128) NOT NULL,
	business_id NVARCHAR(128) NOT NULL,
	rating INTEGER NULL,
	food_rating INTEGER NULL,
	service_rating INTEGER NULL,
	career_id NVARCHAR(128) NULL,
	group_id NVARCHAR(128) NULL,
	career_name NVARCHAR(200) NOT NULL,
	group_name NVARCHAR(200) NOT NULL,
	comment NVARCHAR(max) NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_review_order UNIQUE (order_id),
	CONSTRAINT ck_review_rating CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
	CONSTRAINT ck_review_food_rating CHECK (food_rating IS NULL OR food_rating BETWEEN 1 AND 5),
	CONSTRAINT ck_review_service_rating CHECK (service_rating IS NULL OR service_rating BETWEEN 1 AND 5),
	FOREIGN KEY(order_id) REFERENCES orders (id) ON DELETE NO ACTION,
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE NO ACTION,
	FOREIGN KEY(business_id) REFERENCES businesses (id) ON DELETE NO ACTION,
	FOREIGN KEY(career_id) REFERENCES careers (id) ON DELETE NO ACTION,
	FOREIGN KEY(group_id) REFERENCES academic_groups (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_reviews_business_created ON reviews (business_id, created_at, id);
GO

CREATE TABLE access_decisions (
	id NVARCHAR(128) NOT NULL,
	request_id NVARCHAR(128) NOT NULL,
	user_id NVARCHAR(128) NOT NULL,
	actor_id NVARCHAR(128) NOT NULL,
	decision NVARCHAR(20) NOT NULL,
	role NVARCHAR(20) NOT NULL,
	business_id NVARCHAR(128) NULL,
	note NVARCHAR(500) NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_access_decision_request UNIQUE (request_id),
	FOREIGN KEY(request_id) REFERENCES access_requests (id) ON DELETE NO ACTION,
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE NO ACTION,
	FOREIGN KEY(actor_id) REFERENCES users (id) ON DELETE NO ACTION,
	FOREIGN KEY(business_id) REFERENCES businesses (id) ON DELETE NO ACTION
);
GO

CREATE TABLE push_deliveries (
	id NVARCHAR(128) NOT NULL,
	outbox_event_id INTEGER NOT NULL,
	event_id NVARCHAR(max) NOT NULL,
	device_id NVARCHAR(128) NULL,
	user_id NVARCHAR(128) NOT NULL,
	payload NVARCHAR(max) NOT NULL,
	state NVARCHAR(16) NOT NULL,
	attempts INTEGER NOT NULL,
	next_attempt_at DATETIMEOFFSET NOT NULL,
	locked_until DATETIMEOFFSET NULL,
	lease_id NVARCHAR(max) NULL,
	last_error NVARCHAR(80) NULL,
	provider_message_id NVARCHAR(max) NULL,
	created_at DATETIMEOFFSET NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	sent_at DATETIMEOFFSET NULL,
	PRIMARY KEY (id),
	CONSTRAINT ck_push_state CHECK (state IN ('pending','sending','retry','unconfigured','sent','dead','cancelled')),
	CONSTRAINT ck_push_attempts CHECK (attempts >= 0),
	FOREIGN KEY(outbox_event_id) REFERENCES outbox_events (id) ON DELETE NO ACTION,
	FOREIGN KEY(device_id) REFERENCES devices (id) ON DELETE NO ACTION,
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_push_due ON push_deliveries (state, next_attempt_at);
GO

CREATE UNIQUE INDEX uq_push_event_device ON push_deliveries (outbox_event_id, device_id) WHERE [device_id] IS NOT NULL;
GO

CREATE TABLE product_reviews (
	id NVARCHAR(128) NOT NULL,
	order_id NVARCHAR(128) NOT NULL,
	product_id NVARCHAR(128) NOT NULL,
	user_id NVARCHAR(128) NOT NULL,
	rating INTEGER NOT NULL,
	comment NVARCHAR(max) NOT NULL,
	created_at DATETIMEOFFSET NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_product_review_order_product UNIQUE (order_id, product_id),
	CONSTRAINT ck_product_review_rating CHECK (rating BETWEEN 1 AND 5),
	FOREIGN KEY(order_id) REFERENCES orders (id) ON DELETE NO ACTION,
	FOREIGN KEY(product_id) REFERENCES products (id) ON DELETE NO ACTION,
	FOREIGN KEY(user_id) REFERENCES users (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_product_reviews_user ON product_reviews (user_id);
GO

CREATE INDEX ix_product_reviews_product_created ON product_reviews (product_id, created_at, id);
GO

CREATE TABLE followups (
	review_id NVARCHAR(128) NOT NULL,
	business_id NVARCHAR(128) NOT NULL,
	status NVARCHAR(20) NOT NULL,
	assignee NVARCHAR(120) NOT NULL,
	note NVARCHAR(max) NOT NULL,
	version INTEGER NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (review_id),
	CONSTRAINT ck_followup_version CHECK (version >= 1),
	CONSTRAINT ck_followup_status CHECK (status IN ('pending', 'in_review', 'resolved')),
	FOREIGN KEY(review_id) REFERENCES reviews (id) ON DELETE NO ACTION,
	FOREIGN KEY(business_id) REFERENCES businesses (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_followups_updated ON followups (updated_at, review_id);
GO

CREATE TABLE followup_events (
	id NVARCHAR(128) NOT NULL,
	review_id NVARCHAR(128) NOT NULL,
	business_id NVARCHAR(128) NOT NULL,
	actor_id NVARCHAR(128) NOT NULL,
	status NVARCHAR(20) NOT NULL,
	assignee NVARCHAR(120) NOT NULL,
	note NVARCHAR(max) NOT NULL,
	version INTEGER NOT NULL,
	updated_at DATETIMEOFFSET NOT NULL,
	PRIMARY KEY (id),
	CONSTRAINT uq_followup_event_version UNIQUE (review_id, version),
	CONSTRAINT ck_followup_event_version CHECK (version >= 1),
	CONSTRAINT ck_followup_event_status CHECK (status IN ('pending', 'in_review', 'resolved')),
	FOREIGN KEY(review_id) REFERENCES followups (review_id) ON DELETE NO ACTION,
	FOREIGN KEY(business_id) REFERENCES businesses (id) ON DELETE NO ACTION,
	FOREIGN KEY(actor_id) REFERENCES users (id) ON DELETE NO ACTION
);
GO

CREATE INDEX ix_followup_events_review_version ON followup_events (review_id, version);
GO
