library;

use ::alloc::alloc;
use ::assert::assert;
use ::hash::*;
use ::option::Option::{self, *};
use ::storage::storage_api::*;
use ::storage::storage_key::*;

/// A persistant vector struct.
pub struct StorageVec<V> {}

impl<V> StorageKey<StorageVec<V>> {
    /// Appends the value to the end of the vector.
    ///
    /// # Arguments
    ///
    /// * `value`: [V] - The item being added to the end of the vector.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `3`
    /// * Writes: `2`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     let five = 5_u64;
    ///     storage.vec.push(five);
    ///     assert(five == storage.vec.get(0).unwrap());
    /// }
    /// ```
    #[storage(read, write)]
    pub fn push(self, value: V) {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);

        // Storing the value at the current length index (if this is the first item, starts off at 0)
        let key = sha256((len, self.field_id));
        write::<V>(key, 0, value);

        // Incrementing the length
        write(self.field_id, 0, len + 1);
    }

    /// Removes the last element of the vector and returns it, `None` if empty.
    ///
    /// # Returns
    ///
    /// * [Option<V>] - The last element `V` or `None`.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `3`
    /// * Writes: `1`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     let five = 5_u64;
    ///     storage.vec.push(five);
    ///     let popped_value = storage.vec.pop().unwrap();
    ///     assert(five == popped_value);
    ///     let none_value = storage.vec.pop();
    ///     assert(none_value.is_none())
    /// }
    /// ```
    #[storage(read, write)]
    pub fn pop(self) -> Option<V> {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);

        // if the length is 0, there is no item to pop from the vec
        if len == 0 {
            return None;
        }

        // reduces len by 1, effectively removing the last item in the vec
        write(self.field_id, 0, len - 1);

        let key = sha256((len - 1, self.field_id));
        read::<V>(key, 0)
    }

    /// Gets the value in the given index, `None` if index is out of bounds.
    ///
    /// # Arguments
    ///
    /// * `index`: [u64] - The index of the vec to retrieve the item from.
    ///
    /// # Returns
    ///
    /// * [Option<StorageKey<V>>] - Describes the raw location in storage of the value stored at
    /// `key` or `None` if out of bounds.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     let five = 5_u64;
    ///     storage.vec.push(five);
    ///     assert(five == storage.vec.get(0).unwrap());
    ///     assert(storage.vec.get(1).is_none())
    /// }
    /// ```
    #[storage(read)]
    pub fn get(self, index: u64) -> Option<StorageKey<V>> {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);

        // if the index is larger or equal to len, there is no item to return
        if len <= index {
            return None;
        }

        Some(StorageKey::<V>::new(
            sha256((index, self.field_id)), 
            0, 
            sha256((index, self.field_id))
        ))
    }

    /// Removes the element in the given index and moves all the elements in the following indexes
    /// down one index. Also returns the element.
    ///
    /// # Additional Information
    ///
    ///  **_WARNING:_** Expensive for larger vecs.
    ///
    /// # Arguments
    ///
    /// * `index`: [u64] - The index of the vec to remove the item from.
    /// 
    /// # Returns
    ///
    /// * [V] - The element that has been removed at the index.
    ///
    /// # Reverts
    ///
    /// * Reverts if index is larger or equal to length of the vec.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `3 + (2 * (self.len() - index))`
    /// * Writes: `self.len() - index`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     storage.vec.push(5);
    ///     storage.vec.push(10);
    ///     storage.vec.push(15);
    ///     let removed_value = storage.vec.remove(1);
    ///     assert(10 == removed_value);
    ///     assert(storage.vec.len() == 2);
    /// }
    /// ```
    #[storage(read, write)]
    pub fn remove(self, index: u64) -> V {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);

        // if the index is larger or equal to len, there is no item to remove
        assert(index < len);

        // gets the element before removing it, so it can be returned
        let removed_element = read::<V>(sha256((index, self.field_id)), 0).unwrap();

        // for every element in the vec with an index greater than the input index,
        // shifts the index for that element down one
        let mut count = index + 1;
        while count < len {
            // gets the storage location for the previous index
            let key = sha256((count - 1, self.field_id));
            // moves the element of the current index into the previous index
            write::<V>(key, 0, read::<V>(sha256((count, self.field_id)), 0).unwrap());

            count += 1;
        }

        // decrements len by 1
        write(self.field_id, 0, len - 1);

        removed_element
    }

    /// Removes the element at the specified index and fills it with the last element.
    /// This does not preserve ordering and returns the element.
    ///
    /// # Arguments
    ///
    /// * `index`: [u64] - The index of the vec to remove the item from.
    ///
    /// # Returns
    ///
    /// * [V] - The element that has been removed at the index.
    ///
    /// # Reverts
    ///
    /// * Reverts if index is larger or equal to length of the vec.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `5`
    /// * Writes: `2`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     storage.vec.push(5);
    ///     storage.vec.push(10);
    ///     storage.vec.push(15);
    ///     let removed_value = storage.vec.swap_remove(0);
    ///     assert(5 == removed_value);
    ///     let swapped_value = storage.vec.get(0).unwrap();
    ///     assert(15 == swapped_value);
    /// }
    /// ```
    #[storage(read, write)]
    pub fn swap_remove(self, index: u64) -> V {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);

        // if the index is larger or equal to len, there is no item to remove
        assert(index < len);

        let hash_of_to_be_removed = sha256((index, self.field_id));
        // gets the element before removing it, so it can be returned
        let element_to_be_removed = read::<V>(hash_of_to_be_removed, 0).unwrap();

        let last_element = read::<V>(sha256((len - 1, self.field_id)), 0).unwrap();
        write::<V>(hash_of_to_be_removed, 0, last_element);

        // decrements len by 1
        write(self.field_id, 0, len - 1);

        element_to_be_removed
    }

    /// Sets or mutates the value at the given index.
    ///
    /// # Arguments
    ///
    /// * `index`: [u64] - The index of the vec to set the value at
    /// * `value`: [V] - The value to be set
    ///
    /// # Reverts
    ///
    /// * Reverts if index is larger than or equal to the length of the vec.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `2`
    /// * Writes: `1`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     storage.vec.push(5);
    ///     storage.vec.push(10);
    ///     storage.vec.push(15);
    ///
    ///     storage.vec.set(0, 20);
    ///     let set_value = storage.vec.get(0).unwrap();
    ///     assert(20 == set_value);
    /// }
    /// ```
    #[storage(read, write)]
    pub fn set(self, index: u64, value: V) {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);

        // if the index is higher than or equal len, there is no element to set
        assert(index < len);

        let key = sha256((index, self.field_id));
        write::<V>(key, 0, value);
    }

    /// Inserts the value at the given index, moving the current index's value
    /// as well as the following index's value up by one index.
    ///
    /// # Additional Information
    ///
    /// > **_WARNING:_** Expensive for larger vecs.
    ///
    /// # Arguments
    ///
    /// * `index`: [u64] - The index of the vec to insert the item into.
    /// * `value`: [V] - The value to insert into the vec.
    ///
    /// # Reverts
    ///
    /// * Reverts if index is larger than the length of the vec.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `if self.len() == index { 3 } else { 5 + (2 * (self.len() - index)) }`
    /// * Writes: `if self.len() == index { 2 } else { 2 + self.len() - index }`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     storage.vec.push(5);
    ///     storage.vec.push(15);
    ///
    ///     storage.vec.insert(1, 10);
    ///
    ///     assert(5 == storage.vec.get(0).unwrap());
    ///     assert(10 == storage.vec.get(1).unwrap());
    ///     assert(15 == storage.vec.get(2).unwrap());
    /// }
    /// ```
    #[storage(read, write)]
    pub fn insert(self, index: u64, value: V) {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);

        // if the index is larger than len, there is no space to insert
        assert(index <= len);

        // if len is 0, index must also be 0 due to above check
        if len == index {
            let key = sha256((index, self.field_id));
            write::<V>(key, 0, value);

            // increments len by 1
            write(self.field_id, 0, len + 1);

            return;
        }

        // for every element in the vec with an index larger than the input index,
        // move the element up one index.
        // performed in reverse to prevent data overwriting
        let mut count = len - 1;
        while count >= index {
            let key = sha256((count + 1, self.field_id));
            // shifts all the values up one index
            write::<V>(key, 0, read::<V>(sha256((count, self.field_id)), 0).unwrap());

            if count == 0 { break; }
            count -= 1;
        }

        // inserts the value into the now unused index
        let key = sha256((index, self.field_id));
        write::<V>(key, 0, value);

        // increments len by 1
        write(self.field_id, 0, len + 1);
    }

    /// Returns the length of the vector.
    ///
    /// # Returns
    ///
    /// * [u64] - The stored length of the vector.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     assert(0 == storage.vec.len());
    ///     storage.vec.push(5);
    ///     assert(1 == storage.vec.len());
    ///     storage.vec.push(10);
    ///     assert(2 == storage.vec.len());
    /// }
    /// ```
    #[storage(read)]
    pub fn len(self) -> u64 {
        read::<u64>(self.field_id, 0).unwrap_or(0)
    }

    /// Checks whether the len is zero or not.
    ///
    /// # Returns
    ///
    /// * [bool] - Indicates whether the vector is or is not empty.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     assert(true == storage.vec.is_empty());
    ///
    ///     storage.vec.push(5);
    ///
    ///     assert(false == storage.vec.is_empty());
    ///
    ///     storage.vec.clear();
    ///
    ///     assert(true == storage.vec.is_empty());
    /// }
    /// ```
    #[storage(read)]
    pub fn is_empty(self) -> bool {
        read::<u64>(self.field_id, 0).unwrap_or(0) == 0
    }

    /// Sets the len to zero.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Clears: `1`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     assert(0 == storage.vec.len());
    ///     storage.vec.push(5);
    ///     assert(1 == storage.vec.len());
    ///     storage.vec.clear();
    ///     assert(0 == storage.vec.len());
    /// }
    /// ```
    #[storage(write)]
    pub fn clear(self) {
        let _ = clear::<u64>(self.field_id, 0);
    }

    /// Swaps two elements.
    ///
    /// # Arguments
    ///
    /// * `element1_index`: [u64] - The index of the first element.
    /// * `element2_index`: [u64] - The index of the second element.
    ///
    /// # Reverts
    ///
    /// * If `element1_index` or `element2_index` is greater than the length of the vector.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `5`
    /// * Writes: `2`
    ///
    /// # Examples
    ///
    /// ```sway
    /// use std::storage::storage_vec::*;
    ///
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {}
    /// }
    ///
    /// fn foo() {
    ///     storage.vec.push(5);
    ///     storage.vec.push(10);
    ///     storage.vec.push(15);
    ///
    ///     storage.vec.swap(0, 2);
    ///     assert(15 == storage.vec.get(0).unwrap());
    ///     assert(10 == storage.vec.get(1).unwrap());
    ///     assert(5 == storage.vec.get(2).unwrap());
    /// ```
    #[storage(read, write)]
    pub fn swap(self, element1_index: u64, element2_index: u64) {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);
        assert(element1_index < len);
        assert(element2_index < len);

        if element1_index == element2_index {
            return;
        }

        let element1_key = sha256((element1_index, self.field_id));
        let element2_key = sha256((element2_index, self.field_id));

        let element1_value = read::<V>(element1_key, 0).unwrap();
        write::<V>(element1_key, 0, read::<V>(element2_key, 0).unwrap());
        write::<V>(element2_key, 0, element1_value);
    }

    /// Returns the first element of the vector, or `None` if it is empty.
    ///
    /// # Returns
    ///
    /// * [Option<StorageKey<V>>] - Describes the raw location in storage of the value stored at
    /// the start of the vector or zero if the vector is empty.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    ///
    /// # Examples
    ///
    /// ```sway
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {},
    /// }
    ///
    /// fn foo() {
    ///     assert(storage.vec.first().is_none());
    ///
    ///     storage.vec.push(5);
    ///
    ///     assert(5 == storage.vec.first().unwrwap());
    /// }
    /// ```
    #[storage(read)]
    pub fn first(self) -> Option<StorageKey<V>> {
        match read::<u64>(self.field_id, 0).unwrap_or(0) {
            0 => None,
            _ => Some(StorageKey::<V>::new(
                sha256((0, self.field_id)), 
                0, 
                sha256((0, self.field_id))
            )),
        }
    }

    /// Returns the last element of the vector, or `None` if it is empty.
    ///
    /// # Returns
    ///
    /// * [Option<StorageKey<V>>] - Describes the raw location in storage of the value stored at
    /// the end of the vector or zero if the vector is empty.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    ///
    /// # Examples
    ///
    /// ```sway
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {},
    /// }
    ///
    /// fn foo() {
    ///     assert(storage.vec.last().is_none());
    ///
    ///     storage.vec.push(5);
    ///     storage.vec.push(10);
    ///
    ///     assert(10 == storage.vec.last().unwrap());
    /// }
    /// ```
    #[storage(read)]
    pub fn last(self) -> Option<StorageKey<V>> {
        match read::<u64>(self.field_id, 0).unwrap_or(0) {
            0 => None,
            len => Some(StorageKey::<V>::new(
                sha256((len - 1, self.field_id)), 
                0, 
                sha256((0, self.field_id))
            )),
        }
    }

    /// Reverses the order of elements in the vector, in place.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1 + (3 * (self.len() / 2))`
    /// * Writes: `2 * (self.len() / 2)`
    ///
    /// # Examples
    ///
    /// ```sway
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {},
    /// }
    ///
    /// fn foo() {
    ///     storage.vec.push(5);
    ///     storage.vec.push(10);
    ///     storage.vec.push(15);
    ///     storage.vec.reverse();
    ///
    ///     assert(15 == storage.vec.get(0).unwrap());
    ///     assert(10 == storage.vec.get(1).unwrap());
    ///     assert(5 == storage.vec.get(2).unwrap());
    /// }
    /// ```
    #[storage(read, write)]
    pub fn reverse(self) {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);

        if len < 2 {
            return;
        }

        let mid = len / 2;
        let mut i = 0;
        while i < mid {
            let element1_key = sha256((i, self.field_id));
            let element2_key = sha256((len - i - 1, self.field_id));

            let element1_value = read::<V>(element1_key, 0).unwrap();
            write::<V>(element1_key, 0, read::<V>(element2_key, 0).unwrap());
            write::<V>(element2_key, 0, element1_value);

            i += 1;
        }
    }

    /// Fills `self` with elements by cloning `value`.
    ///
    /// # Arguments
    ///
    /// * `value`: [V] - Value to copy to each element of the vector.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1 + self.len()`
    /// * Writes: `self.len()`
    ///
    /// # Examples
    ///
    /// ```sway
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {},
    /// }
    ///
    /// fn foo() {
    ///     storage.vec.push(5);
    ///     storage.vec.push(10);
    ///     storage.vec.push(15);
    ///     storage.vec.fill(20);
    ///
    ///     assert(20 == storage.vec.get(0).unwrap());
    ///     assert(20 == storage.vec.get(1).unwrap());
    ///     assert(20 == storage.vec.get(2).unwrap());
    /// }
    /// ```
    #[storage(read, write)]
    pub fn fill(self, value: V) {
        let len = read::<u64>(self.field_id, 0).unwrap_or(0);

        let mut i = 0;
        while i < len {
            write::<V>(sha256((i, self.field_id)), 0, value);
            i += 1;
        }
    }

    /// Resizes `self` in place so that `len` is equal to `new_len`.
    ///
    /// # Additional Information
    ///
    /// If `new_len` is greater than `len`, `self` is extended by the difference, with each
    /// additional slot being filled with `value`. If the `new_len` is less than `len`, `self` is
    /// simply truncated.
    ///
    /// # Arguments
    ///
    /// * `new_len`: [u64] - The new length to expand or truncate to
    /// * `value`: [V] - The value to fill into new slots if the `new_len` is greater than the current length
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads - `if new_len > self.len() { new_len - len + 2 } else { 2 }`
    /// * Writes - `if new_len > self.len() { new_len - len + 1 } else { 1 }`
    ///
    /// # Examples
    ///
    /// ```sway
    /// storage {
    ///     vec: StorageVec<u64> = StorageVec {},
    /// }
    ///
    /// fn foo() {
    ///     storage.vec.push(5);
    ///     storage.vec.push(10);
    ///     storage.vec.resize(4, 20);
    ///
    ///     assert(5 == storage.vec.get(0).unwrap());
    ///     assert(10 == storage.vec.get(1).unwrap());
    ///     assert(20 == storage.vec.get(2).unwrap());
    ///     assert(20 == storage.vec.get(3).unwrap());
    ///
    ///     storage.vec.resize(2, 0);
    ///
    ///     assert(5 == storage.vec.get(0).unwrap());
    ///     assert(10 == storage.vec.get(1).unwrap());
    ///     assert(None == storage.vec.get(2));
    ///     assert(None == storage.vec.get(3));
    /// }
    /// ```
    #[storage(read, write)]
    pub fn resize(self, new_len: u64, value: V) {
        let mut len = read::<u64>(self.field_id, 0).unwrap_or(0);
        while len < new_len {
            write::<V>(sha256((len, self.field_id)), 0, value);
            len += 1;
        }
        write::<u64>(self.field_id, 0, new_len);
    }
}
