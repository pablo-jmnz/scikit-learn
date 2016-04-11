# Authors: Gilles Louppe <g.louppe@gmail.com>
#          Peter Prettenhofer <peter.prettenhofer@gmail.com>
#          Brian Holt <bdholt1@gmail.com>
#          Joel Nothman <joel.nothman@gmail.com>
#          Arnaud Joly <arnaud.v.joly@gmail.com>
#          Jacob Schreiber <jmschreiber91@gmail.com>
#
# Licence: BSD 3 clause

# See _splitter.pyx for details.

import numpy as np
cimport numpy as np

from ._criterion cimport Criterion

ctypedef np.npy_float32 DTYPE_t          # Type of X
ctypedef np.npy_float64 DOUBLE_t         # Type of y, sample_weight
ctypedef np.npy_intp SIZE_t              # Type for indices and counters
ctypedef np.npy_uint8 UINT8_t            # Unsigned 8 bit integer
ctypedef np.npy_int32 INT32_t            # Signed 32 bit integer
ctypedef np.npy_uint32 UINT32_t          # Unsigned 32 bit integer
ctypedef np.npy_uint64 UINT64_t          # Unsigned 64 bit integer

ctypedef union SplitValue:
    # Union type to generalize the concept of a threshold to
    # categorical features. For non-categorical features, use the
    # threshold member. It acts just as before, where feature values
    # less than or equal to the threshold go left, and values greater
    # than the threshold go right.
    #
    # For categorical features, use the cat_split member. It works in
    # one of two ways, indicated by the value of its least significant
    # bit (LSB). If the LSB is 0, then cat_split acts as a bitfield
    # for up to 64 categories, sending samples left if the bit
    # corresponding to their category is 1 or right if it is 0. If the
    # LSB is 1, then the more significant 32 bits of cat_split is a
    # random seed. To evaluate a sample, use the random seed to flip a
    # coin (category_value + 1) times and send it left if the last
    # flip gives 1; otherwise right. This second method allows up to
    # 2**31 category values, but can only be used for RandomSplitter.
    DOUBLE_t threshold
    UINT64_t cat_split
    UINT8_t* cat_two

cdef struct SplitRecord:
    # Data to track sample split
    SIZE_t feature         # Which feature to split on.
    SIZE_t pos             # Split samples array at the given position,
                           # i.e. count of samples below threshold for feature.
                           # pos is >= end if the node is a leaf.
    SplitValue split_value # Generalized threshold for categorical and
                           # non-categorical features.
    double improvement     # Impurity improvement given parent node.
    double impurity_left   # Impurity of the left split.
    double impurity_right  # Impurity of the right split.

cdef class Splitter:
    # The splitter searches in the input space for a feature and a threshold
    # to split the samples samples[start:end].
    #
    # The impurity computations are delegated to a criterion object.

    # Internal structures
    cdef public Criterion criterion      # Impurity criterion
    cdef public SIZE_t max_features      # Number of features to test
    cdef public SIZE_t min_samples_leaf  # Min samples in a leaf
    cdef public double min_weight_leaf   # Minimum weight in a leaf

    cdef object random_state             # Random state
    cdef UINT32_t rand_r_state           # sklearn_rand_r random number state

    cdef SIZE_t* samples                 # Sample indices in X, y
    cdef SIZE_t n_samples                # X.shape[0]
    cdef double weighted_n_samples       # Weighted number of samples
    cdef SIZE_t* features                # Feature indices in X
    cdef SIZE_t* constant_features       # Constant features indices
    cdef SIZE_t n_features               # X.shape[1]
    cdef DTYPE_t* feature_values         # temp. array holding feature values

    cdef SIZE_t start                    # Start position for the current node
    cdef SIZE_t end                      # End position for the current node

    cdef bint presort                    # Whether to use presorting, only
                                         # allowed on dense data

    cdef DOUBLE_t* y
    cdef SIZE_t y_stride
    cdef DOUBLE_t* sample_weight
    cdef INT32_t* n_categories           # (n_features) array giving number of
                                         # categories (<0 for non-categorical)
    cdef UINT8_t* _bit_cache
    
    cdef bint twoclass                   # Binary classification
    cdef INT32_t max_n_categories

    # The samples vector `samples` is maintained by the Splitter object such
    # that the samples contained in a node are contiguous. With this setting,
    # `node_split` reorganizes the node samples `samples[start:end]` in two
    # subsets `samples[start:pos]` and `samples[pos:end]`.

    # The 1-d  `features` array of size n_features contains the features
    # indices and allows fast sampling without replacement of features.

    # The 1-d `constant_features` array of size n_features holds in
    # `constant_features[:n_constant_features]` the feature ids with
    # constant values for all the samples that reached a specific node.
    # The value `n_constant_features` is given by the parent node to its
    # child nodes.  The content of the range `[n_constant_features:]` is left
    # undefined, but preallocated for performance reasons
    # This allows optimization with depth-based tree building.

    # Methods
    cdef void init(self, object X, np.ndarray y,
                   DOUBLE_t* sample_weight,
                   INT32_t* n_categories,
                   bint twoclass,
                   np.ndarray X_idx_sorted=*) except *

    cdef void node_reset(self, SIZE_t start, SIZE_t end,
                         double* weighted_n_node_samples) nogil

    cdef void node_split(self,
                         double impurity,   # Impurity of the node
                         SplitRecord* split,
                         SIZE_t* n_constant_features) nogil

    cdef void node_value(self, double* dest) nogil

    cdef double node_impurity(self) nogil
