-- DateDiff function that returns the difference between two timestamps in the given date_part (weeks, months, etc) as an integer
-- This behaves like the DateDiff function in warehouses like Redshift and Snowflake, which count the boundaries between date_parts
CREATE OR REPLACE FUNCTION datediff (date_part VARCHAR(30), start_t TIMESTAMP, end_t TIMESTAMP)
  RETURNS INT AS $diff$

  DECLARE
    years INT = 0;
    days INT = 0;
    hours INT = 0;
    minutes INT = 0;  
  BEGIN

    -- year is straightforward. Convert to an integer representing the year and subtract
    years = DATE_PART('year', end_t) - DATE_PART('year', start_t);

    IF date_part IN ('y', 'yr', 'yrs', 'year', 'years')  THEN
      RETURN years;
    END IF;

    -- quarter and month use integer math: count years, multiply to convert to quarters or months
    -- as an integer and then subtract

    IF date_part IN ('quarter', 'quarters', 'qtr', 'qtrs')  THEN
      RETURN years * 4 + (DATE_PART('quarter', end_t) - DATE_PART('quarter', start_t)); 
    END IF;

    IF date_part IN ('month', 'months', 'mon', 'mons')  THEN
      RETURN years * 12 + (DATE_PART('month', end_t) - DATE_PART('month', start_t)); 
    END IF;


    -- Weeks only fit evenly in days.  
    -- Truncate by week (which returns the start of the first day of the week)
    -- then subtract by days.
    IF date_part IN ('week', 'weeks', 'w') THEN
      RETURN DATE_PART('day', (DATE_TRUNC('week', end_t) - DATE_TRUNC('week', start_t)) / 7);
    END IF;


    -- Day is similar to week. Truncate to beginning of day so that we can diff whole days
    days = DATE_PART('day', DATE_TRUNC('day', end_t) - DATE_TRUNC('day', start_t));

    IF date_part IN ('day', 'days', 'd') THEN
      RETURN days;
    END IF;
    
    -- hours, minutes, and seconds all just build up from each other
    hours = days * 24 + (DATE_PART('hour', end_t) - DATE_PART('hour', start_t));

    IF date_part IN ('hour', 'hours', 'h', 'hr', 'hrs') THEN
      RETURN hours;
    END IF;


    minutes = hours * 60 + (DATE_PART('minute', end_t) - DATE_PART('minute', start_t));

    IF date_part IN ('minute', 'minutes', 'm', 'min', 'mins') THEN
      RETURN minutes;
    END IF;


    IF date_part IN ('second', 'seconds', 's', 'sec', 'secs') THEN
      RETURN minutes * 60 + (DATE_PART('second', end_t) - DATE_PART('second', start_t));
    END IF;


    RETURN 0;
END;
$diff$ LANGUAGE plpgsql;

/* 
    ###################
    # Wei Howe's Code #
    ###################  
*/

CREATE OR REPLACE PROCEDURE add_employee
    -- This assumes that the employee will always have minimally a mobilenum
    (IN e_name VARCHAR(50), IN mobilenum VARCHAR(50), IN kind VARCHAR(50), IN d_id INTEGER, IN homenum VARCHAR(50) DEFAULT NULL, IN officenum VARCHAR(50) DEFAULT NULL)
AS $$
DECLARE 
new_eid INTEGER:= 0;
new_email VARCHAR(50);
BEGIN

    SELECT max(eid) INTO new_eid FROM Employees;
    IF (new_eid IS NULL) 
        THEN new_eid = 1;
    ELSE
        new_eid:= new_eid + 1;
    END IF;

    SELECT CONCAT(CAST(new_eid AS VARCHAR(50)), '@demo_company.com') into new_email;

    /*
    SELECT max(eid) INTO new_eid FROM Employees;
    IF (last_eid IS NULL)
        new_email := CONCAT(1, '@demo_company.com');
    ELSE
        new_eid:= (new_eid + 1)::varchar(50);
        new_email:= CONCAT(new_eid, '@demo_company.com');
    END IF;*/
    
    -- Is there a better way of generating the eid than using AUTOINCREMENT?
    INSERT INTO Employees(ename, mobile_num, home_num, office_num, email, role, did)
    VALUES (e_name, mobilenum, homenum, officenum, new_email, kind, d_id);

    -- Removed insertion of junior/manager/senior here and instead put in trigger help_insert_role()
END;
$$LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE remove_employee
    (IN e_id INTEGER, IN resign_d DATE)
AS $$
BEGIN
    UPDATE Employees
    SET resigned_date = resign_d
    WHERE eid = e_id;
END;
$$LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION view_future_meeting
    (IN start_date DATE, IN e_id INTEGER)
RETURNS TABLE (date DATE, start_hour TIME, room INTEGER, floor INTEGER) AS $$
BEGIN
    SELECT j.date, j.time, j.room, j.floor 
    FROM Joins j, Approves a
    WHERE j.date = a.date
        AND j.time = a.time
        AND j.room = a.room
        AND j.floor = a.floor
        AND j.eid = e_id
        AND j.date >= start_date
    ORDER BY j.date, j.time ASC;
END;
$$LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION view_manager_report
    (IN start_date DATE, IN e_id INTEGER)
RETURNS TABLE (date DATE, start_hour TIME, room INTEGER, floor INTEGER, m_eid INTEGER) AS $$
DECLARE 
manager_did INTEGER:= 0;
BEGIN
    -- If not manager, do nothing
    IF e_id IN (SELECT eid FROM Manager)
    THEN 
    SELECT did INTO manager_did FROM Employee WHERE eid = m_eid;
    END IF;

    -- Get all meetings not approved yet using left join
    WITH all_na AS (
        SELECT * 
        FROM Books b
        LEFT JOIN Approves a 
        ON b.date = a.date
        AND b.time = a.time
        AND b.room = a.room
        AND b.floor = a.floor
        WHERE a.date = NULL
    )

    --Only select meetings which the booker and the manager is from the same department
    SELECT all_na.date, all_na.time, all_na.room, all_na.floor, all_na.eid
    FROM all_na, employee e
    WHERE all_na.eid = e.eid
    AND e.did = manager_did
    AND all_na.date >= start_date
    ORDER BY all_na.date, all_na.time ASC;
END;
$$LANGUAGE plpgsql;


/* 
    ###################
    # Wei Xuan's Code #
    ###################  */

--add_room routine
/*
a manager is needed to add a room as the capacity has to be decided by someone
whenever a room is newly added, we assume that the room is not available for booking
on that day, as this was not specified by the document.
*/
CREATE OR REPLACE PROCEDURE add_room
	(floor INTEGER, room INTEGER, rname VARCHAR(50), room_capacity INTEGER, did INTEGER, mid INTEGER, date DATE)
AS $$
BEGIN
    INSERT INTO Meeting_Rooms 
    VALUES(floor, room, rname, did);
    INSERT INTO Updates 
    VALUES(date, floor, room, room_capacity, mid);
END;
$$LANGUAGE plpgsql;


--change_capacity routine
CREATE OR REPLACE PROCEDURE change_capacity
    (floor INTEGER, room INTEGER, new_capacity INTEGER, date DATE)
AS $$
BEGIN
    INSERT INTO Updates
    VALUES (date, floor, room, room_capacity, mid);
END;
$$LANGUAGE plpgsql;


/* search_room routine: 
1st step: get all entries in Updates where date is before query_date
2nd step: filter out Updates so that only the max(date) for each (floor,room) remains --> latest update
3rd step: filter out Updates where new_cap >= required_cap 
4th step: return rooms where --> floor, room not in Books where time >=start_hour and time < end_hour
*/

CREATE OR REPLACE FUNCTION search_room
    (IN required_cap INTEGER, IN query_date DATE, IN start_hour TIME, IN end_hour TIME)
RETURNS TABLE(floor INTEGER, room INTEGER, did INTEGER, available_capacity INTEGER) AS $$
BEGIN
    --get the latest updates: step 1 and 2
    WITH latest_updates AS (
        SELECT floor, room, MAX(date)
        FROM Updates
        WHERE date <= query_date
        GROUP BY floor, room
    ),

    --get the rooms with capactity >= required capacity: step 3
    -- e.g. 3 floor, room which meets the required capacity
    cap_available AS (
        SELECT floor, room, did, new_cap
        FROM Updates as u JOIN Meeting_Rooms as m
        ON u.floor = m.floor
            AND u.room = m.room
        WHERE EXISTS (SELECT 1
                        FROM latest_updates as lu
                        WHERE lu.floor = floor
                            AND lu.room = room
                            AND lu.date = date)
        ORDER BY new_cap ASC
    )

    --step 4:
    SELECT floor, room, did, new_cap
    FROM cap_available AS c
    WHERE NOT EXISTS (SELECT 1
                        FROM Books AS b
                        WHERE b.time >= start_hour
                            AND b.time < end_hour
                            AND b.floor = c.floor
                            AND b.room = c.room);
    RETURN NEXT; --need to confirm if required
END;
$$ LANGUAGE plpgsql;

/*
step 1: get all the rooms which were booked
step 2: check if they are approved
*/

CREATE OR REPLACE FUNCTION view_booking_report
    (IN start_date DATE, IN bid INTEGER)
RETURNS TABLE(floor INTEGER, room INTEGER, date DATE, start_hour TIME, is_approved BOOLEAN) AS $$
BEGIN
    WITH booked_rooms AS (
        SELECT *
        FROM Books as b JOIN Approves as a
        ON b.date = a.date
            AND b.time = a.time
            AND b.floor = a.floor
            AND b.room = a.room
        WHERE date >= start_date
            AND b.bid = bid
    )


    SELECT floor, room, date, time, CASE
        WHEN aid IS NULL THEN FALSE
        ELSE TRUE
      END AS is_approved
    FROM booked_rooms;
END;
$$ LANGUAGE plpgsql;


/*
    ###################
    #    Jon Code     #
    ###################  */

--book_room
CREATE OR REPLACE PROCEDURE book_room
    (IN floor INTEGER, IN room INTEGER, IN date DATE, IN start_hour TIME, IN end_hour TIME, IN eid INTEGER)
AS $$
DECLARE
    number_of_hours INTEGER := 0;
    booking_hour TIME := start_hour;
BEGIN
--find number of hours is the booking
--for loop through the number of hours and add the start hour to books, with start hour incrementing by 1 hour after every insertion
    number_of_hours := DATE_PART('hour', end_hour - start_hour);
    WHILE number_of_hours > 0 LOOP
        number_of_hours := number_of_hours - 1;
        INSERT INTO Books VALUES (eid, date, booking_hour, floor, room);
        select booking_hour + interval '1 hour' into booking_hour;
    END LOOP;
END;
$$ LANGUAGE plpgsql; --no works

--CREATE OR REPLACE PROCEDURE add_booking
--    (IN eid INTEGER, IN date DATE, IN start_hour TIME, IN floor INTEGER, IN room INTEGER)
--AS $$
--BEGIN
--    INSERT INTO Books VALUES (eid, date, start_hour, floor, room);
--END;
--$$ LANGUAGE plpgsql; --this works

--unbook_room
/*
All participants removed via the Foreign Key constraint
--> On delete cascade for joins and approves
*/
CREATE OR REPLACE PROCEDURE unbook_room
    (IN floor INTEGER, IN room INTEGER, IN date DATE, IN start_hour TIME, IN end_hour TIME, IN eid INTEGER)
AS $$
DECLARE
    number_of_hours INTEGER := 0;
    booking_hour TIME := start_hour;
BEGIN
    number_of_hours := DATE_PART('hour', end_hour - start_hour);
    WHILE number_of_hours > 0 LOOP
        number_of_hours := number_of_hours - 1;
        CALL remove_booking(eid, date, booking_hour, room, floor);
        booking_hour := booking_hour + interval '1 hour';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE remove_booking
     (IN eid INTEGER, IN date DATE, IN start_hour TIME, IN room INTEGER, IN floor INTEGER)
AS $$
BEGIN
    DELETE FROM Books
    WHERE eid = Books.eid
    AND floor = Books.floor
    AND room = Books.room
    AND date = Books.date
    AND start_hour = Books.time;

    -- Should be unecessary because once it is deleted from books it will automatically
    -- be deleted from approves via the FK Constraint
    /*DELETE FROM Approves
    WHERE floor = Approves.floor
    AND room = Approves.room
    AND date = Approves.date
    AND start_hour = Approves.time;*/
END;
$$ LANGUAGE plpgsql;

--join_meeting
CREATE OR REPLACE PROCEDURE join_meeting
    (IN floor INTEGER, IN room INTEGER, IN date DATE, IN start_hour TIME, IN end_hour TIME, IN eid INTEGER)
AS $$
DECLARE
    number_of_hours INTEGER := 0;
    booking_hour TIME := start_hour;
BEGIN
    number_of_hours := DATE_PART('hour', end_hour - start_hour);
    WHILE number_of_hours > 0 LOOP
        number_of_hours := number_of_hours - 1;
        CALL add_to_meeting(eid, date, booking_hour, room, floor);
        booking_hour := booking_hour + interval '1 hour';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE add_to_meeting
    (IN eid INTEGER, IN date DATE, IN start_hour TIME, IN room INTEGER, IN floor INTEGER)
AS $$
BEGIN
    INSERT INTO Joins VALUES (eid, date, start_hour, floor, room);
END;
$$ LANGUAGE plpgsql;



--leave_meeting
CREATE OR REPLACE PROCEDURE leave_meeting
    (IN floor INTEGER, IN room INTEGER, IN date DATE, IN start_hour TIME, IN end_hour TIME, IN eid INTEGER)
AS $$
DECLARE
    number_of_hours INTEGER := 0;
    booking_hour TIME := start_hour;
BEGIN
    number_of_hours := DATE_PART('hour', end_hour - start_hour);
    WHILE number_of_hours > 0 LOOP
        number_of_hours := number_of_hours - 1;
        CALL remove_from_meeting(eid, date, booking_hour, room, floor);
        booking_hour := booking_hour + interval '1 hour';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE remove_from_meeting
    (IN eid INTEGER, IN date DATE, IN start_hour TIME, IN room INTEGER, IN floor INTEGER)
AS $$
BEGIN
    DELETE FROM Joins
    WHERE floor = Joins.floor
    AND room = Joins.room
    AND date = Joins.date
    AND start_hour = Joins.time
    AND eid = Joins.eid;
END;
$$ LANGUAGE plpgsql;

--approve_meeting
CREATE OR REPLACE PROCEDURE approve_meeting
    (IN floor INTEGER, IN room INTEGER, IN date DATE, IN start_hour TIME, IN end_hour TIME, IN eid INTEGER)
AS $$
DECLARE
    number_of_hours INTEGER := 0;
    booking_hour TIME := start_hour;
BEGIN
    number_of_hours := DATE_PART('hour', end_hour - start_hour);
    WHILE number_of_hours > 0 LOOP
        number_of_hours := number_of_hours - 1;
        CALL approve_the_meeting(eid, date, booking_hour, room, floor);
        booking_hour := booking_hour + interval '1 hour';
    END LOOP;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE approve_the_meeting
    (IN eid INTEGER, IN date DATE, IN start_hour TIME, IN room INTEGER, IN floor INTEGER)
AS $$
BEGIN
    INSERT INTO Approves VALUES (eid, date, start_hour, floor, room);
END;
$$ LANGUAGE plpgsql;

/* 
    ###################
    # Zhen Hong's Code #
    ###################  */

CREATE OR REPLACE PROCEDURE add_department
    (IN did INTEGER, IN dname VARCHAR(50))
AS $$
BEGIN
    INSERT INTO departments
    VALUES (did, dname);
END;
$$LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE remove_department
    (IN d_id INTEGER)
AS $$
BEGIN
    DELETE FROM departments
    WHERE (did = d_id);
END;
$$LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE declare_health
    (IN eid INTEGER, IN date DATE, IN temp NUMERIC)
AS $$
DECLARE
    has_fever BOOLEAN := FALSE;
BEGIN
    IF (temp > 37.5) 
        THEN has_fever = TRUE;
    END IF;
    INSERT INTO Health_Declaration
    VALUES (eid, date, temp, has_fever);
END;
$$LANGUAGE plpgsql;



--non compliance
/*

*/
CREATE OR REPLACE FUNCTION non_compliance
    (IN start_date date, IN end_date date)
RETURNS TABLE(eid INTEGER, days BIGINT) AS $$
DECLARE
    total_days INTEGER;
BEGIN
    /*
    WITH employees_not_declared AS (
        WHILE curr_date <= end_date LOOP

            SELECT e.eid
            FROM Employees AS e
            WHERE e.eid NOT IN (SELECT hd.eid
                            FROM Health_Declaration as hd
                            WHERE hd.date < start_date
                            AND hd.date > end_date);

            DATEADD(day, 1, curr_date);

        END LOOP
    )

    SELECT eid, COUNT(*) FROM employees_not_declared
    GROUP BY eid
    ORDER BY COUNT(*) desc;
    */

    total_days := end_date - start_date + 1; --**CHECK WHETHER NEED TO PLUS ONE**

    
    
    
    WITH declared_days AS (
        SELECT Health_Declaration.eid, (total_days - COUNT(*)) AS days
            FROM Health_Declaration
            WHERE date >= start_date
                AND date <= end_date
            GROUP BY Health_Declaration.eid
            ORDER BY days DESC;
    )

    no_declaration AS (
        SELECT eid, total_days as days
        FROM Employees
        WHERE eid NOT IN SELECT * FROM declared_days;
    )

    RETURN QUERY SELECT * 
        FROM  no_declaration UNION declared_days
        WHERE days <> 0;

    /*    
    WITH declared_days AS (
        SELECT Health_Declaration.eid, total_days - COUNT(*) AS days
        FROM Health_Declaration
        WHERE date >= start_date
            AND date <= end_date
        GROUP BY Health_Declaration.eid
        HAVING days < total_days
        ORDER BY days ASC
    )

    UPDATE declared_days
    SET days = total_days - days;

    SELECT * FROM declared_days;
    */

END;
$$LANGUAGE plpgsql;

--contact tracing
/*
step 1: check if employee is having fever -> IF NO FEVER --> RETURN;
ELSE:
    step 1: remove all bookings by employee
    step 2: check approved meeting room containing employee
    step 3: create table of all employess in those meeting rooms
    step 4: remove close contact employees from meetings for next 7 days --> check eid in JOINS and date > current_date 
*/

/*
    Wei Xuan's Comment: Missing Books & Approved
*/

CREATE OR REPLACE FUNCTION contact_tracing
    (IN e_id INTEGER)
RETURNS TABLE(eid INTEGER) AS $$
DECLARE 
    has_fever BOOLEAN;
    curr_date DATE;
BEGIN
    has_fever := GET fever FROM Health_Declaration WHERE eid = e_id;
    IF has_fever = 0 THEN RETURN;
    END IF;

    WITH compromised_meetings AS (
        SELECT date, time, room, floor
        FROM Joins
        WHERE eid = e_id
            AND date >= DATEADD(day, -3, curr_date)
            AND date <= curr_date
    ),

    compromised_employees AS (
        SELECT eid from Joins
        WHERE compromised_meetings.date = Joins.date
        AND compromised_meetings.time = Joins.time
        AND compromised_meetings.room = Joins.room
        AND compromised_meetings.floor = Joins.floor
    ),

    bookings_to_cancel AS (
        SELECT date, time, room, floor
        FROM Books
        WHERE Books.eid = e_id
            AND (Books.date > CURRENT_DATE OR (Books.date = CURRENT_DATE AND LOCALTIME > Books.time))
    )

    DELETE FROM Joins
    WHERE compromised_employees.eid = Joins.eid
    AND Joins.date >= curr_date
    AND Joins.date <= DATEADD(day, 7, curr_date);

    DELETE FROM Books
    WHERE Books.date = bookings_to_cancel.date
    AND Books.time = bookings_to_cancel.time
    AND Books.room = bookings_to_cancel.room
    AND Books.floor = bookings_to_cancel.floor;

    SELECT * FROM compromised_employees;
END;
$$LANGUAGE plpgsql;

