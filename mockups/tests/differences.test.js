'use strict';
const assert = require('node:assert/strict');
const {test} = require('node:test');
const {readFileSync} = require('node:fs');
const {runInNewContext} = require('node:vm');
const sandbox = {window:{},document:{createElement:()=>({})}};
runInNewContext(readFileSync(`${__dirname}/../differences.js`,'utf8'),sandbox);
const {inkDifference,rank} = sandbox.window.GlyphDifferences;
const rgba = alpha => Uint8ClampedArray.from(alpha.flatMap(a=>[255,255,255,a]));

test('empty and identical ink have no difference',()=>{
  assert.equal(inkDifference(rgba([0,0]),rgba([0,0])),0);
  assert.equal(inkDifference(rgba([255,127]),rgba([255,127])),0);
});
test('disjoint ink differs completely',()=>{
  assert.equal(inkDifference(rgba([255,0]),rgba([0,255])),1);
});
test('fractional coverage uses intersection/union and is symmetric',()=>{
  const a=rgba([255,128,0]),b=rgba([255,0,64]);
  const expected=1-255/(255+128+64);
  assert.equal(inkDifference(a,b),expected);
  assert.equal(inkDifference(b,a),expected);
});
test('each independent toggle sorts by its own metric',()=>{
  const scores=[{char:'a',shape:.8,spacing:.01},{char:'@',shape:.2,spacing:.06}];
  assert.equal(rank(scores,{shape:true})[0].char,'a');
  assert.equal(rank(scores,{spacing:true})[0].char,'@');
});
test('combined ranking is invariant to metric units and input order',()=>{
  const scores=[{char:'a',shape:.8,spacing:.01},{char:'@',shape:.2,spacing:.06},{char:'x',shape:.7,spacing:.07}];
  const order=data=>rank(data,{shape:true,spacing:true}).map(x=>x.char).join('');
  assert.equal(order(scores),'xa@');
  assert.equal(order(scores),order([...scores].reverse().map(x=>({...x,spacing:x.spacing*1000}))));
  assert.equal(rank(scores,{}).map(x=>x.char).join(''),order(scores));
});
test('ties are stable and identical fonts do not acquire synthetic scores',()=>{
  const scores=[{char:'b',shape:0,spacing:0},{char:'a',shape:0,spacing:0}];
  const result=rank(scores,{shape:true,spacing:true});
  assert.equal(result.map(x=>x.char).join(''),'ab');
  assert.ok(result.every(x=>x.score===0));
});
