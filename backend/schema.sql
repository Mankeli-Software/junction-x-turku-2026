-- AMRight schema. Safe to run repeatedly: every statement is IF NOT EXISTS.
-- Dataset tables mirror the CSV columns in data/synthetic_microbiology_dataset/ (see its README).

CREATE TABLE IF NOT EXISTS wards (
    ward_code   text PRIMARY KEY,
    ward_fi     text NOT NULL,
    ward_en     text NOT NULL,
    ward_type   text NOT NULL CHECK (ward_type IN ('in', 'out')),
    institution text NOT NULL
);

CREATE TABLE IF NOT EXISTS antibiotics (
    antibiotic      text NOT NULL,
    antibiotic_code text PRIMARY KEY,
    antibiotic_fi   text NOT NULL,
    class           text NOT NULL,
    reported_for    text NOT NULL
);

CREATE TABLE IF NOT EXISTS patients (
    patient_id text PRIMARY KEY,
    sex        text NOT NULL CHECK (sex IN ('F', 'M')),
    birth_year integer NOT NULL,
    home_area  text NOT NULL
);

CREATE TABLE IF NOT EXISTS cultures (
    culture_id     text PRIMARY KEY,
    patient_id     text NOT NULL REFERENCES patients (patient_id),
    age_years      integer NOT NULL,
    sample_date    date NOT NULL,
    iso_year       integer NOT NULL,
    iso_week       integer NOT NULL,
    ward_code      text NOT NULL REFERENCES wards (ward_code),
    ward_fi        text NOT NULL,
    ward_en        text NOT NULL,
    ward_type      text NOT NULL CHECK (ward_type IN ('in', 'out')),
    institution    text NOT NULL,
    admission_date date,            -- inpatients only
    specimen       text NOT NULL CHECK (specimen IN ('urine', 'blood', 'wound')),
    specimen_fi    text NOT NULL,
    result         text NOT NULL CHECK (result IN ('positive', 'negative', 'mixed_growth')),
    n_isolates     integer NOT NULL
);

CREATE TABLE IF NOT EXISTS isolates (
    isolate_id text PRIMARY KEY,
    culture_id text NOT NULL REFERENCES cultures (culture_id),
    isolate_no integer NOT NULL,
    organism   text NOT NULL,
    quantity   text,                -- urine CFU/ml or wound +..+++; empty for blood
    esbl       smallint NOT NULL CHECK (esbl IN (0, 1)),
    mrsa       smallint NOT NULL CHECK (mrsa IN (0, 1)),
    vre        smallint NOT NULL CHECK (vre IN (0, 1)),
    cpe        smallint NOT NULL CHECK (cpe IN (0, 1))
);

CREATE TABLE IF NOT EXISTS susceptibility (
    isolate_id      text NOT NULL REFERENCES isolates (isolate_id),
    culture_id      text NOT NULL REFERENCES cultures (culture_id),
    organism        text NOT NULL,
    antibiotic      text NOT NULL,
    antibiotic_code text NOT NULL REFERENCES antibiotics (antibiotic_code),
    antibiotic_fi   text NOT NULL,
    -- The data has only S and R; I is allowed because EUCAST defines it (see issue #1).
    result          text NOT NULL CHECK (result IN ('S', 'I', 'R')),
    guideline       text NOT NULL,
    PRIMARY KEY (isolate_id, antibiotic_code)
);

CREATE INDEX IF NOT EXISTS cultures_patient_idx     ON cultures (patient_id);
CREATE INDEX IF NOT EXISTS cultures_sample_date_idx ON cultures (sample_date);
CREATE INDEX IF NOT EXISTS cultures_ward_idx        ON cultures (ward_code);
CREATE INDEX IF NOT EXISTS cultures_specimen_idx    ON cultures (specimen);
CREATE INDEX IF NOT EXISTS isolates_culture_idx     ON isolates (culture_id);
CREATE INDEX IF NOT EXISTS isolates_organism_idx    ON isolates (organism);
CREATE INDEX IF NOT EXISTS susceptibility_culture_idx    ON susceptibility (culture_id);
CREATE INDEX IF NOT EXISTS susceptibility_antibiotic_idx ON susceptibility (antibiotic_code);

-- Application tables. Only what exists today; add the others (weekly_aggregates, alerts,
-- widget_usage, agent_recordings) with the issues that use them.
CREATE TABLE IF NOT EXISTS user_dashboards (
    user_id    text PRIMARY KEY,
    role       text NOT NULL,
    layout     jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
