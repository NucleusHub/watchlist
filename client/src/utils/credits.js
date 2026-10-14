// Port of CustomCredit.Job in ios/Watchlist/Model/Records.swift.
export const CREW_JOBS = ['Director', 'Creator', 'Writer', 'Producer', 'Composer', 'Cinematographer', 'Editor']

const DEPARTMENT_JOB = {
  Directing: 'Director', Writing: 'Writer', Production: 'Producer',
  Sound: 'Composer', Camera: 'Cinematographer', Editing: 'Editor',
}

// The job someone known for a TMDb department most likely had; null for actors.
export const jobForDepartment = (department) => DEPARTMENT_JOB[department] ?? null

export function creditFromPerson(person) {
  const job = jobForDepartment(person.knownFor)
  return { name: person.name, role: job ?? '', cast: job === null, personId: person.id, photo: person.photo ?? null }
}

const JOB_DEPARTMENT = { Creator: 'Writing', ...Object.fromEntries(Object.entries(DEPARTMENT_JOB).map(([d, j]) => [j, d])) }

// Hand-entered credits as plugins see them; personID 0 means not on TMDb. Port of PluginCredits(custom:).
export function pluginCredits(custom) {
  const credit = (c) => ({
    personID: c.personId ?? 0,
    name: c.name,
    role: c.role || '',
    department: c.cast !== false ? 'Acting' : (JOB_DEPARTMENT[c.role] ?? 'Crew'),
    photoURL: c.photo ?? null,
  })
  const list = (custom ?? []).filter((c) => c?.name)
  return { cast: list.filter((c) => c.cast !== false).map(credit), crew: list.filter((c) => c.cast === false).map(credit) }
}
