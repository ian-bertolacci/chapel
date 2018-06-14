/* Performance testing of different aspects of LayoutCS

*/
config const seed : int(64) =  SeedGenerator.oddCurrentTime;

use Time;
use Random;
use LayoutCS;

class PerfTest {
  proc init(){ }
  proc name() : string {
    return "PerfTest";
  }
  proc run() : Timer {
    halt( "Empty PerfTest." );
    return new Timer();
  }
}

class LayoutCSTest : PerfTest {
  param compressRows : bool;
  var sorted : bool;
  const numRows : int, numCols : int;
  const numberNonZeros : int;

  proc init( param compressRows : bool, sorted : bool, numRows : int, numCols : int, numberNonZeros : int ){
    this.compressRows = compressRows;
    this.sorted = sorted;
    this.numRows = numRows;
    this.numCols = numCols;
    this.numberNonZeros = numberNonZeros;
    assert( this.numRows > 0, "numRows cannot be less than 1" );
    assert( this.numCols > 0, "numCols cannot be less than 1" );
    assert( this.numberNonZeros > 0, "numberNonZeros cannot be less than 1" );
  }

  proc nameArgs() : string {
    return  "compressRows=" + (this.compressRows:string)
          + ",sorted=" + (this.sorted:string)
          + ",numRows=" + (this.numRows:string)
          + ",numCols=" + (this.numCols:string)
          + ",numberNonZeros=" + (this.numberNonZeros:string);
  }

  proc name() : string {
    return "LayoutCSTest(" + this.nameArgs() + ")";
  }

  proc run() : Timer {
    halt( "Empty LayoutCSTest." );
    return new Timer();
  }
}

class DomainIndexInsertion : LayoutCSTest {
  proc init( param compressRows : bool, sorted : bool, numRows : int, numCols : int, numberNonZeros : int ){
    super.init( compressRows, sorted, numRows, numCols, numberNonZeros );
  }

  proc name() : string {
    return "DomainIndexInsertion(" + this.nameArgs() + ")";
  }

  proc run() : Timer {
    var D : domain(2) = {1..#numRows, 1..#numCols};
    var sD : sparse subdomain(D) dmapped CS( compressRows = this.compressRows, sorted = this.sorted );
    var all_indices = [idx in D] idx;
    shuffle( all_indices, seed = seed );
    var used_indices = all_indices[1..#this.numberNonZeros];

    var timer = new Timer();

    timer.start();
    for idx in used_indices {
      sD += idx;
    }
    timer.stop();

    return timer;
  }
}

class DomainIndexRemoval : LayoutCSTest {
  proc init( param compressRows : bool, sorted : bool, numRows : int, numCols : int, numberNonZeros : int ){
    super.init( compressRows, sorted, numRows, numCols, numberNonZeros );
  }

  proc name() : string {
    return "DomainIndexRemoval(" + this.nameArgs() + ")";
  }

  proc run() : Timer {
    var D : domain(2) = {1..#numRows, 1..#numCols};
    var sD : sparse subdomain(D) dmapped CS( compressRows = this.compressRows, sorted = this.sorted );
    var all_indices = [idx in D] idx;
    shuffle( all_indices, seed = seed );
    var used_indices = all_indices[1..#this.numberNonZeros];

    for idx in used_indices {
      sD += idx;
    }

    shuffle( used_indices, seed = seed );
    var timer = new Timer();

    timer.start();
    for idx in used_indices {
      sD -= idx;
    }
    timer.stop();

    return timer;
  }
}

class DomainIndexIsMember : LayoutCSTest {
  proc init( param compressRows : bool, sorted : bool, numRows : int, numCols : int, numberNonZeros : int ){
    super.init( compressRows, sorted, numRows, numCols, numberNonZeros );
  }

  proc name() : string {
    return "DomainIndexIsMember(" + this.nameArgs() + ")";
  }

  proc run(){
    var D : domain(2) = {1..#numRows, 1..#numCols};
    var sD : sparse subdomain(D) dmapped CS( compressRows = this.compressRows, sorted = this.sorted );
    var all_indices = [idx in D] idx;
    shuffle( all_indices, seed = seed );
    var used_indices = all_indices[1..#this.numberNonZeros];

    for idx in used_indices {
      sD += idx;
    }

    shuffle( used_indices, seed = seed );
    var timer = new Timer();
    var contains_all = true;

    timer.start();
    for idx in used_indices {
      contains_all &= sD.member( idx );
    }
    timer.stop();

    if ! contains_all then halt( this.name() + " error: Did not contain all.");

    return timer;
  }
}

class DomainIndexIsNotMember : LayoutCSTest {
  proc init( param compressRows : bool, sorted : bool, numRows : int, numCols : int, numberNonZeros : int ){
    super.init( compressRows, sorted, numRows, numCols, numberNonZeros );
  }

  proc name() : string {
    return "DomainIndexIsNotMember(" + this.nameArgs() + ")";
  }

  proc run(){
    var D : domain(2) = {1..#numRows, 1..#numCols};
    var sD : sparse subdomain(D) dmapped CS( compressRows = this.compressRows, sorted = this.sorted );
    var all_indices = [idx in D] idx;
    shuffle( all_indices, seed = seed );
    var used_indices = all_indices[1..#this.numberNonZeros];

    for idx in used_indices {
      sD += idx;
    }


    var timer = new Timer();
    var contains_any = false;
    var all_anti_D = [idx in { ..0 #-numRows, ..0 #-numCols }] idx;
    shuffle( all_anti_D, seed = seed );
    var used_anti_D = all_anti_D[1..#this.numberNonZeros];


    timer.start();
    for idx in used_anti_D {
      contains_any |= sD.member( idx );
    }
    timer.stop();

    if contains_any then halt( this.name() + " error: Did contain at least one.");

    return timer;
  }
}

class DomainIndexInsertWithLivingArray : LayoutCSTest {
  proc init( param compressRows : bool, sorted : bool, numRows : int, numCols : int, numberNonZeros : int ){
    super.init( compressRows, sorted, numRows, numCols, numberNonZeros );
  }

  proc name() : string {
    return "DomainIndexInsertWithLivingArray(" + this.nameArgs() + ")";
  }

  proc run(){
    var D : domain(2) = {1..#numRows, 1..#numCols};
    var sD : sparse subdomain(D) dmapped CS( compressRows = this.compressRows, sorted = this.sorted );
    var array : [sD] int(8);
    var all_indices = [idx in D] idx;
    shuffle( all_indices, seed = seed );
    var used_indices = all_indices[1..#this.numberNonZeros];

    var timer = new Timer();
    timer.start();
    for idx in used_indices {
      sD += idx;
    }
    timer.stop();

    array[used_indices[used_indices.domain.last]] = 255 : int(8);

    if array[used_indices[used_indices.domain.last]] & 1 != 1 then halt( this.name() + " error: failed the dead code test.");

    return timer;
  }
}

// Test add
class ArrayInsert : LayoutCSTest {
  const random_order : bool;

  proc init( param compressRows : bool, sorted : bool, numRows : int, numCols : int, numberNonZeros : int, random_order : bool ){
    super.init( compressRows, sorted, numRows, numCols, numberNonZeros );
    this.random_order = random_order;
  }

  proc name() : string {
    return "ArrayInsert(" + this.nameArgs() + ",random_order=" + (random_order : bool) + ")";
  }

  proc run(){
    var D : domain(2) = {1..#numRows, 1..#numCols};
    var sD : sparse subdomain(D) dmapped CS( compressRows = this.compressRows, sorted = this.sorted );
    var all_indices = [idx in D] idx;
    shuffle( all_indices, seed = seed );
    var used_indices = all_indices[1..#this.numberNonZeros];

    for idx in used_indices {
      sD += idx;
    }

    var array : [sD] int(8);

    var timer = new Timer();

    if random_order {
      shuffle( used_indices, seed = seed );

      timer.start();
      for idx in used_indices {
        array[idx] = (idx[1] & 0xFE) : int(8);
      }
      timer.stop();
    } else {
      timer.start();
      for idx in sD {
        array[idx] = (idx[1] & 0xFE) : int(8);
      }
      timer.stop();
    }

    if array[used_indices[used_indices.domain.last]] & 1 != 0 then halt( this.name() + " error: failed the dead code test.");

    return timer;
  }
}

class ArrayRead : LayoutCSTest {
  const random_order : bool;

  proc init( param compressRows : bool, sorted : bool, numRows : int, numCols : int, numberNonZeros : int, random_order : bool ){
    super.init( compressRows, sorted, numRows, numCols, numberNonZeros );
    this.random_order = random_order;
  }

  proc name() : string {
    return "ArrayRead(" + this.nameArgs() + ",random_order=" + (random_order : bool) + ")";
  }

  proc run(){
    var D : domain(2) = {1..#numRows, 1..#numCols};
    var sD : sparse subdomain(D) dmapped CS( compressRows = this.compressRows, sorted = this.sorted );
    var all_indices = [idx in D] idx;
    shuffle( all_indices, seed = seed );
    var used_indices = all_indices[1..#this.numberNonZeros];

    for idx in used_indices {
      sD += idx;
    }

    var array : [sD] int(8);

    for idx in sD {
      array[idx] = (idx[1] & 0xFE) : int(8);
    }

    var timer = new Timer();
    var copy_array : [D] int(8);
    if random_order {
      shuffle( used_indices, seed = seed );

      timer.start();
      for idx in used_indices {
        copy_array[idx] = array[idx];
      }
      timer.stop();
    } else {
      timer.start();
      for idx in sD {
        copy_array[idx] = array[idx];
      }
      timer.stop();
    }

    if copy_array[used_indices[used_indices.domain.first]] & 1 != 0 then halt( this.name() + " error: failed the dead code test.");

    return timer;
  }
}

config const numRows = 10;
config const numCols = 1000;
config const portions = 10;

proc main(){

  var numberNonZeros_list : [1..portions] int;
  for i in 1..portions do numberNonZeros_list[i] = (i)*((numRows*numCols)/portions);
  numberNonZeros_list[portions] = (numRows*numCols);
  writeln( numberNonZeros_list );
  for numberNonZeros in numberNonZeros_list {
    for param compressRows in true..true {
      for sorted in false..true {
        writeln( (compressRows: bool , sorted : bool , numberNonZeros) );
        for test in [
          new DomainIndexInsertion( compressRows : bool, sorted : bool , numRows, numCols, numberNonZeros ) : PerfTest,
          new DomainIndexRemoval( compressRows : bool, sorted : bool , numRows, numCols, numberNonZeros ) : PerfTest,
          new DomainIndexIsMember( compressRows : bool, sorted : bool , numRows, numCols, numberNonZeros ) : PerfTest,
          new DomainIndexIsNotMember( compressRows : bool, sorted : bool , numRows, numCols, numberNonZeros ) : PerfTest,
          new DomainIndexInsertWithLivingArray( compressRows : bool, sorted : bool , numRows, numCols, numberNonZeros ) : PerfTest,
          new ArrayInsert( compressRows : bool, sorted : bool , numRows, numCols, numberNonZeros, random_order=true ) : PerfTest,
          new ArrayInsert( compressRows : bool, sorted : bool , numRows, numCols, numberNonZeros, random_order=false ) : PerfTest,
          new ArrayRead( compressRows : bool, sorted : bool , numRows, numCols, numberNonZeros, random_order=true ) : PerfTest,
          new ArrayRead( compressRows : bool, sorted : bool , numRows, numCols, numberNonZeros, random_order=false ) : PerfTest,
        ] {
          writeln( test.name(), ":\t\t", test.run().elapsed() );
        }
      }
    }
  }
}
